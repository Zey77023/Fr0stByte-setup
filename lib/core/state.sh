#!/bin/bash

# Stage broker + resource registry + stage ledger.
# Journal is append-only, tab separated. Keys/values must not contain tabs.

if [[ ${_SOURCED_core_state:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_state="loaded"

module::provide core.state \
    state_set state_get state_has state_unset \
    register_mount register_mapper cleanup_target \
    state::load state::sync state::journal_reset \
    state::ledger_mark state::ledger_status state::ledger_has_active

declare -gA _STATE=() _STAGE_LEDGER=()
declare -ga INSTALLER_MOUNTS=() INSTALLER_MAPPERS=()

: "${INSTALLER_STATE_FILE:=/run/fr0stbyte-installer.state}"
: "${LUKS_NAME:=cryptroot}"
: "${MAPPER_DEV:=/dev/mapper/$LUKS_NAME}"

# Parse the journal into memory.
state::load() {
    local line a b c rest records=0
    # NOTE: plain `_STATE=()` would drop the associative attribute; keep it.
    unset _STATE _STAGE_LEDGER
    declare -gA _STATE=() _STAGE_LEDGER=()
    INSTALLER_MOUNTS=()
    INSTALLER_MAPPERS=()
    [[ -f $INSTALLER_STATE_FILE ]] || return 0
    while IFS= read -r line || [[ -n $line ]]; do
        IFS=$'\t' read -r a b c rest <<<"$line"
        case "$a" in
            mount)
                INSTALLER_MOUNTS+=("$b")
                ;;
            mapper)
                INSTALLER_MAPPERS+=("$b")
                ;;
            STATE)
                _STATE[$b]="$c"
                ;;
            STAGE)
                _STAGE_LEDGER[$b]="$c"
                ;;
        esac
        records=$((records + 1))
    done <"$INSTALLER_STATE_FILE"
    debug_msg "State journal loaded ($records records from $INSTALLER_STATE_FILE)"
    return 0
}

# Re-read journal into memory (call after a stage's subshell may have
# journaled keys without this parent process seeing them).
state::sync() {
    state::load
}

# Write to state journal
state::__persist() {
    local IFS=$'\t'
    mkdir -p "$(dirname -- "$INSTALLER_STATE_FILE")"
    printf '%s\n' "$*" >>"$INSTALLER_STATE_FILE"
}

# Store a key value pair and write it to the state journal
state_set() {
    local key="$1" value="$2"
    if [[ ! $key =~ ^[a-zA-Z0-9_/.-]+$ ]]; then
        error_msg "state_set: invalid key: $key"
        return 1
    fi
    value="${value//$'\t'/ }"
    value="${value//$'\n'/ }"
    _STATE[$key]="$value"
    state::__persist STATE "$key" "$value"
    return 0
}

# Get the value for a key from the state journal
state_get() {
    local key="$1" default="${2:-}"
    if [[ -n ${_STATE[$key]+x} ]]; then
        printf '%s\n' "${_STATE[$key]}"
        return 0
    fi
    if [[ -n "$default" ]]; then
        debug_msg "state_get: '$key' not set, returning default"
        printf '%s\n' "$default"
    fi
    return 0
}

# Check if the state records have state for the requested key
state_has() {
    [[ -n ${_STATE[$1]+x} ]] || return 1
    return 0
}

# Remove a state record from the state records
state_unset() {
    unset "_STATE[$1]" 2>/dev/null
    return 0
}

# Record a mount/mapper resource in memory and journal.
register_mount() {
    local mountpoint="$1"
    if [[ " ${INSTALLER_MOUNTS[*]:-} " == *" $mountpoint "* ]]; then
        debug_msg "register_mount: duplicate registration ignored: $mountpoint"
        return 0
    fi
    INSTALLER_MOUNTS+=("$mountpoint")
    state::__persist mount "$mountpoint"
    return 0
}

register_mapper() {
    local mapper="$1"
    if [[ " ${INSTALLER_MAPPERS[*]:-} " == *" $mapper "* ]]; then
        debug_msg "register_mapper: duplicate registration ignored: $mapper"
        return 0
    fi
    INSTALLER_MAPPERS+=("$mapper")
    state::__persist mapper "$mapper"
    return 0
}

#   cleanup_target [mnt]
cleanup_target() {
    local mnt="${1:-${TARGET_MNT:-/mnt}}"
    local mapper mountpoint
    local -a cleanup_mounts=()
    local remaining_mounts remaining_mappers default_mapper

    if ((${#INSTALLER_MOUNTS[@]} == 0 && ${#INSTALLER_MAPPERS[@]} == 0)); then
        state::load
    fi
    debug_msg "cleanup_target: sweeping mounts and mappers under $mnt"

    while IFS= read -r mountpoint; do
        [[ -n "$mountpoint" ]] && cleanup_mounts+=("$mountpoint")
    done < <(findmnt -rn -o TARGET -R --target "$mnt" 2>/dev/null | sort)
    cleanup_mounts+=("${INSTALLER_MOUNTS[@]}")

    for ((i = ${#cleanup_mounts[@]} - 1; i >= 0; i--)); do
        mountpoint="${cleanup_mounts[$i]}"
        if mountpoint -q "$mountpoint" 2>/dev/null; then
            debug_msg "Unmounting installer mount: $mountpoint"
            umount "$mountpoint" 2>/dev/null || warn_msg "Could not unmount $mountpoint"
        fi
    done

    default_mapper="${MAPPER_DEV##*/}"
    # SC1087 after variable expansion.
    if [[ -n "$default_mapper"
        && " ${INSTALLER_MAPPERS[*]:-} " != *" $default_mapper "* ]]; then
        INSTALLER_MAPPERS+=("$default_mapper")
    fi

    for ((i = ${#INSTALLER_MAPPERS[@]} - 1; i >= 0; i--)); do
        mapper="${INSTALLER_MAPPERS[$i]}"
        if [[ -b "/dev/mapper/$mapper" ]]; then
            debug_msg "Closing installer mapper: $mapper"
            cryptsetup close "$mapper" 2>/dev/null || warn_msg "Could not close $mapper"
        fi
    done

    remaining_mounts=$(findmnt -rn -o TARGET -R --target "$mnt" 2>/dev/null || true)
    remaining_mappers=""
    for mapper in "${INSTALLER_MAPPERS[@]}"; do
        if [[ -b "/dev/mapper/$mapper" ]]; then
            remaining_mappers+="$mapper\\n"
        fi
    done
    if [[ -z "$remaining_mounts" && -z "$remaining_mappers" ]]; then
        rm -f "$INSTALLER_STATE_FILE"
    fi
    return 0
}

state::journal_reset() {
    rm -f "$INSTALLER_STATE_FILE"
    state::load
    return 0
}

# ---- stage ledger ---------------------------------------------------------

# state::ledger_mark <stage-id> <RUNNING|DONE|FAILED>
state::ledger_mark() {
    local id="$1" status="$2"
    _STAGE_LEDGER[$id]="$status"
    state::__persist STAGE "$id" "$status" "$(date -u +%s)"
    return 0
}

# state::ledger_status <stage-id>
# Check if the stage is running, done or failed
state::ledger_status() {
    local id="$1"
    if [[ -n ${_STAGE_LEDGER[$id]+x} ]]; then
        printf '%s\n' "${_STAGE_LEDGER[$id]}"
        return 0
    fi
    return 1
}

# Prints ids of RUNNING|FAILED stages; rc 0 when any found.
state::ledger_has_active() {
    local -a active=()
    local stage_id
    for stage_id in "${!_STAGE_LEDGER[@]}"; do
        case "${_STAGE_LEDGER[$stage_id]}" in
            RUNNING | FAILED)
                active+=("$stage_id")
                ;;
        esac
    done
    if ((${#active[@]} == 0)); then
        return 1
    fi
    printf '%s\n' "${active[@]}" | sort
    return 0
}

return 0
