#!/bin/bash

# Validation helper core

if [[ ${_SOURCED_validation_core_check:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_validation_core_check="loaded"

module::provide validation.check \
    check::fail check::is_dryrun check::is_uefi check::is_root \
    check::require_file check::require_state \
    check::assert_whole_disk check::assert_no_mounts check::assert_no_swap_on \
    check::assert_parttype check::assert_state_keys \
    check::assert_command_succeeded

# check::fail <msg> — log and fail the current validation check.
check::fail() {
    error_msg "$1"
    return 1
}

# check::is_dryrun — true when validations must skip non-state assertions.
check::is_dryrun() {
    [[ ${FR0ST_DRYRUN:-0} == "1" ]]
}

# check::is_uefi — UEFI boot required across every supported install path.
check::is_uefi() {
    [[ -d /sys/firmware/efi/efivars ]]
}

# check::is_root — the installer performs privileged operations.
check::is_root() {
    (( EUID == 0 ))
}

# check::require_file <path> — path exists.
check::require_file() {
    [[ -e $1 ]] || check::fail "required path missing: $1"
}

# check::require_state <key> [stage_hint] — state key must exist.
check::require_state() {
    if ! declare -F state_has >/dev/null; then
        error_msg "check::require_state needs core.state — add it to VALIDATE_APIS"
        return 1
    fi
    if state_has "$1"; then
        return 0
    fi
    error_msg "validation: required state key '$1' missing${2:+ (validating stage $2)}"
    return 1
}

# check::assert_whole_disk <dev> — check if the device is a valid block device.
check::assert_whole_disk() {
    local dev="$1"
    if ! [[ -b $dev ]]; then
        check::fail "Target is not a block device: $dev"
        return 1
    fi
    if [[ "$(lsblk -dn -o TYPE "$dev")" != "disk" ]]; then
        check::fail "Target must be a whole disk, not a partition: $dev"
        return 1
    fi
    return 0
}

# check::assert_no_mounts <dev> — the disk has no mounted filesystems.
check::assert_no_mounts() {
    local dev="$1"
    if lsblk -nrpo MOUNTPOINTS "$dev" | grep -q '[^[:space:]]'; then
        check::fail "Target disk has mounted filesystems: $dev"
        return 1
    fi
    return 0
}

# check::assert_no_swap_on <dev> — no active swap on any device of <dev>.
check::assert_no_swap_on() {
    local dev="$1"
    local -a devices=()
    local swap
    mapfile -t devices < <(lsblk -nrpo NAME "$dev")
    while IFS= read -r swap; do
        [[ -n $swap ]] || continue
        if printf '%s\n' "${devices[@]}" | grep -Fxq "$swap"; then
            check::fail "Target disk has active swap: $swap"
            return 1
        fi
    done < <(swapon --noheadings --raw --output NAME 2>/dev/null || true)
    return 0
}

# check::assert_parttype <dev> <uuid> — the partition's type GUID should match the readback from the device.
check::assert_parttype() {
    local dev="$1" want="$2" got
    got="$(lsblk -no PARTTYPE "$dev" 2>/dev/null | tr '[:upper:]' '[:lower:]' | head -n1)"
    [[ "$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" == "$got" ]] || \
        check::fail "$dev partition type is '$got', expected '$want'"
}

# check::assert_state_keys <key…> [stage_hint] — plural require_state.
check::assert_state_keys() {
    local keys=("$@") key hint="" rc_total=0
    if (($# > 0)); then
        local last="${keys[$# - 1]}"
        if [[ "$last" != */* ]]; then
            hint="$last"
            keys=("${keys[@]:0:$# - 1}")
        fi
    fi
    for key in "${keys[@]}"; do
        check::require_state "$key" "$hint" || rc_total=1
    done
    return "$rc_total"
}

# check::assert_command_succeeded <mnt> <cmd…> — run a command inside the target chroot and require exit 0.
check::assert_command_succeeded() {
    local mnt="$1"
    shift
    if ! declare -F chroot_exec >/dev/null; then
        error_msg "check::assert_command_succeeded needs system.chroot — add it to VALIDATE_APIS"
        return 1
    fi
    chroot_exec "$mnt" -- "$@" || { check::fail "chroot probe failed: $*"; return 1; }
    return 0
}

return 0
