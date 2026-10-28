#!/bin/bash

# Fr0stByte — opinionated Arch Linux installer.
# Usage: ./install.sh --help

# Exit on error, unset variable, or error in pipeline
set -euEo pipefail

# --- Installer anchors ---
INSTALLER_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
INSTALLER_UTILS="$INSTALLER_ROOT/util"
INSTALLER_LIB="$INSTALLER_ROOT/lib"

export FR0ST_LIB_ROOT="$INSTALLER_LIB"
export FR0ST_VALIDATION_ROOT="$INSTALLER_ROOT/validation"
export FR0ST_ASSETS_ROOT="$INSTALLER_ROOT/assets"
export FR0ST_RUN_DIR="${FR0ST_RUN_DIR:-/run/fr0stbyte}"
export INSTALLER_STATE_FILE="${FR0ST_STATE_FILE:-/run/fr0stbyte-installer.state}"
export TARGET_MNT="${TARGET_MNT:-/mnt}"

# --- Stage environment ---
export LUKS_NAME="${LUKS_NAME:-cryptroot}"
export MAPPER_DEV="${MAPPER_DEV:-/dev/mapper/$LUKS_NAME}"
export BOOT_LABEL="FROSTEFI"
export ROOT_LABEL="FROSTROOT"
export FR0ST_SCRIPT_DEPS="${FR0ST_SCRIPT_DEPS:-$INSTALLER_LIB/pkg/lists/script-dependencies}"
export FR0ST_PACSTRAP_PKGS="${FR0ST_PACSTRAP_PKGS:-$INSTALLER_LIB/pkg/lists/pacstrap-packages}"
export FR0ST_DIAG_PKGS="${FR0ST_DIAG_PKGS:-$INSTALLER_LIB/pkg/lists/optional-diagnostic-packages}"
export FR0ST_FONT_PKGS="${FR0ST_FONT_PKGS:-$INSTALLER_LIB/pkg/lists/font-packages}"

# --- Logging ---
export LOG_FILE="${LOG_FILE:-$INSTALLER_ROOT/install.log}"
export TRACE_LOG_FILE="${TRACE_LOG_FILE:-$INSTALLER_ROOT/install.trace.log}"
: >"$LOG_FILE"

# --- Core modules ---
FR0ST_CORE_MODULES=("core.checks" "core.config" "core.exec" "core.exit_codes" "core.logging" "core.secret" "core.state" "core.trace" "core.trap" "core.ui")

# NOTE: module.sh is the root dependency of every other core module, so
# NOTE: it cannot go through module::source here.
source "$INSTALLER_LIB/core/module.sh"

# --- Import core modules ---
for _fr0st_core in "${FR0ST_CORE_MODULES[@]}"; do
    # shellcheck disable=SC1090
    module::source "$_fr0st_core"
done
unset _fr0st_core

# --- CLI helpers ---
# cli::die <message> — styled CLI rejection + usage hint
cli::die() {
    error_msg "$1"
    status_msg "Run './install.sh --help' for usage."
    exit "$EXIT_INTERNAL"
}

# cli::require_value <flag> <value> — reject a flag missing its value
cli::require_value() {
    if [[ -z "${2:-}" || "$2" == --* ]]; then
        cli::die "$1 needs a value"
    fi
    return 0
}

# cli::usage — options the installer accepts
cli::usage() {
    cat <<'USAGE'
Fr0stByte — opinionated Arch Linux installer.

Options:
  --list-stages          list the contract stages and exit
  --stage <id>           run only stage <id>, even when the ledger says DONE
  --redo <id>            re-run stage <id> alone, even when ledger-DONE
                         (the only way to redo destructive 03/05)
  --resume [<id>]        skip ledger-DONE stages (optionally from <id>)
  --from-scratch         wipe the target and state journal, then run everything
  --profile <file>       load profile overrides on top of config/defaults.conf
  --trace                verbose trace log (install.trace.log)
  --dry-run              plan only: no mutations, no root needed
  --help, -h             show this help
USAGE
}

# --- Installer stage helpers ---
# NOTE: functions which involve sourcing stage files to extract data run in a
# NOTE: separate bash shell to avoid pulluting the parent shell namespace

# stage::metadata_of <file> — print "id|kind|desc" for one stage file
stage::metadata_of() {
    local file="$1"
    bash -c '
        # shellcheck disable=SC1090,SC2034
        source "$1"
        printf "%s|%s|%s\n" "${STAGE_ID:-}" "${STAGE_KIND:-}" "${STAGE_DESC:-}"
    ' _ "$file" 2>/dev/null || printf '%s|%s|%s\n' "" "" ""
}

# stage::apis_of <file> — print the STAGE_APIS of one stage file
stage::apis_of() {
    local file="$1"
    bash -c '
        # shellcheck disable=SC1090
        source "$1"
        if [[ -n "${STAGE_APIS[*]:-}" ]]; then
            printf "%s\n" "${STAGE_APIS[*]}"
        fi
    ' _ "$file" 2>/dev/null || true
}

# stage::list — print every stages/*.sh path (nullglob: never a literal glob)
stage::list() {
    local -a files=()
    shopt -s nullglob
    files=("$INSTALLER_ROOT"/stages/*.sh)
    shopt -u nullglob
    ((${#files[@]} > 0)) || return 0
    printf '%s\n' "${files[@]}"
    return 0
}

# stage::discover — fill STAGE_FILES; fail when no stages are found
stage::discover() {
    mapfile -t STAGE_FILES < <(stage::list)
    if ((${#STAGE_FILES[@]} == 0)); then
        cli::die "no stage files found under $INSTALLER_ROOT/stages"
    fi
    return 0
}

# stage::known <id> — id matches a discovered NN-name stage file
stage::known() {
    local file
    for file in "${STAGE_FILES[@]}"; do
        [[ "${file##*/}" == "$1.sh" ]] && return 0
    done
    return 1
}


# --- CLI flags resolution ---
FR0ST_LIST_STAGES=0
FR0ST_ONLY_STAGE=""
FR0ST_REDO_STAGE=""
FR0ST_RESUME=0
FR0ST_RESUME_FROM=""
FR0ST_FROM_SCRATCH=0
FR0ST_PROFILE_FILE=""
FR0ST_FLAG_STAGE=0
FR0ST_FLAG_REDO=0

while [[ $# -gt 0 ]]; do
    case "$1" in
    --list-stages)
        FR0ST_LIST_STAGES=1
        shift
        ;;
    --stage)
        cli::require_value "--stage" "${2:-}"
        FR0ST_ONLY_STAGE="$2"
        FR0ST_FLAG_STAGE=1
        shift 2
        ;;
    --redo)
        cli::require_value "--redo" "${2:-}"
        FR0ST_REDO_STAGE="$2"
        FR0ST_FLAG_REDO=1
        FR0ST_ONLY_STAGE="$2"
        shift 2
        ;;
    --resume)
        FR0ST_RESUME=1
        shift
        if [[ -n "${1:-}" && "$1" != --* ]]; then
            FR0ST_RESUME_FROM="$1"
            shift
        fi
        ;;
    --from-scratch)
        FR0ST_FROM_SCRATCH=1
        shift
        ;;
    --trace)
        export FR0ST_TRACE=1
        shift
        ;;
    --profile)
        cli::require_value "--profile" "${2:-}"
        FR0ST_PROFILE_FILE="$2"
        shift 2
        ;;
    --dry-run)
        export FR0ST_DRYRUN=1
        shift
        ;;
    --help | -h)
        cli::usage
        exit 0
        ;;
    *)
        cli::die "Unknown option: $1"
        ;;
    esac
done

# --- CLI flags validation ---

if ((FR0ST_FLAG_STAGE && FR0ST_FLAG_REDO)); then
    cli::die "--stage and --redo are mutually exclusive"
fi
if ((FR0ST_FROM_SCRATCH)) && ((FR0ST_RESUME || FR0ST_FLAG_STAGE || FR0ST_FLAG_REDO)); then
    cli::die "--from-scratch cannot be combined with --resume/--stage/--redo"
fi
if [[ -n "$FR0ST_PROFILE_FILE" && ! -f "$FR0ST_PROFILE_FILE" ]]; then
    cli::die "--profile file not found: $FR0ST_PROFILE_FILE"
fi

stage::discover

for _fr0st_wanted in "$FR0ST_ONLY_STAGE" "$FR0ST_REDO_STAGE" "$FR0ST_RESUME_FROM"; do
    [[ -n "$_fr0st_wanted" ]] || continue
    stage::known "$_fr0st_wanted" ||
        cli::die "unknown stage id: $_fr0st_wanted (see --list-stages)"
done
unset _fr0st_wanted

# --- Installer banner ---
cat <<'EOF' | tee -a "$LOG_FILE"
    ______     ____       __  ____        __
   / ____/____/ __ \_____/ /_/ __ )__  __/ /____
  / /_  / ___/ / / / ___/ __/ __  / / / / __/ _ \
 / __/ / /  / /_/ (__  ) /_/ /_/ / /_/ / /_/  __/
/_/   /_/   \____/____/\__/_____/\__, /\__/\___/
                                /____/
EOF

debug_msg "Installer root anchored at: $INSTALLER_ROOT"
debug_msg "Logging to: $LOG_FILE"

# --- Load installer defaults and overrides from the configuration file ---
if [[ ! -f "$INSTALLER_ROOT/config/defaults.conf" ]]; then
    cp "$INSTALLER_ROOT/config/defaults.conf.dist" "$INSTALLER_ROOT/config/defaults.conf"
    warn_msg "config/defaults.conf was missing; restored the shipped default"
fi
defaults::load "$INSTALLER_ROOT/config/defaults.conf"
if [[ -n "$FR0ST_PROFILE_FILE" ]]; then
    defaults::profile_load "$FR0ST_PROFILE_FILE"
    status_msg "profile: overrides loaded from $FR0ST_PROFILE_FILE"
fi

# --- Tracing log ---
trace::init "$TRACE_LOG_FILE"
if [[ ${FR0ST_TRACE:-0} == "1" ]]; then
    set -x
    debug_msg "trace: enabled → $TRACE_LOG_FILE"
fi

# --- Traps ---
trap::install

# ! Cleanup is not guaranteed when the shell is force-killed; resume
# ! re-attaches what the journal still describes (resume::verify_mounts).
trap 'trace::stop' EXIT

# --- List stages ---
if ((FR0ST_LIST_STAGES)); then
    for stage_file in "${STAGE_FILES[@]}"; do
        IFS='|' read -r stage_id stage_kind stage_desc < <(stage::metadata_of "$stage_file")
        printf '%-14s %-12s %s\n' "$stage_id" "$stage_kind" "$stage_desc"
    done
    exit 0
fi

# --- Resume mechanics ---
state::load

# wipe_target_journal <label> — reset the state journal from the target
wipe_target_journal() {
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: $1 would sweep + wipe journal ($INSTALLER_STATE_FILE)"
        return 0
    fi
    debug_msg "$1: cleanup resources and wipe the journal"
    cleanup_target "$TARGET_MNT"
    state::journal_reset
}

# resume::verify_mounts — prune journaled mounts/mappers that no longer exist
resume::verify_mounts() {
    local mp mapper
    local -a keep_mounts=() keep_mappers=()
    for mp in "${INSTALLER_MOUNTS[@]}"; do
        if mountpoint -q "$mp" 2>/dev/null; then
            keep_mounts+=("$mp")
        else
            warn_msg "resume: journaled mount is gone (stage must recreate): $mp"
        fi
    done
    INSTALLER_MOUNTS=("${keep_mounts[@]}")
    for mapper in "${INSTALLER_MAPPERS[@]}"; do
        if [[ -b "/dev/mapper/$mapper" ]]; then
            keep_mappers+=("$mapper")
        else
            warn_msg "resume: journaled mapper is gone (stage must recreate): $mapper"
        fi
    done
    INSTALLER_MAPPERS=("${keep_mappers[@]}")
    return 0
}

# * --resume only suppresses the prompt below; resume logic is handled
# * in the run loop's ledger checks.
mapfile -t _resume_active < <(state::ledger_has_active || true)

if ((FR0ST_FROM_SCRATCH)); then
    wipe_target_journal "--from-scratch"
elif ((${#_resume_active[@]} > 0)) && ((FR0ST_RESUME == 0)) &&
    [[ -z "$FR0ST_ONLY_STAGE" ]]; then
    status_msg "A previous run left these stages unfinished: ${_resume_active[*]}"
    _resume_detail="$(state_get stages/last_failure)"
    if [[ -n "$_resume_detail" ]]; then
        status_msg "Last failure: $_resume_detail"
    fi
    resume_choice=$(ui::choose "Resume the previous installation?" \
        "Resume" \
        "Start from scratch") || true
    case "${resume_choice:-}" in
    Resume)
        FR0ST_RESUME=1
        ;;
    *)
        wipe_target_journal "resume start-over"
        ;;
    esac
else
    debug_msg "resume: no unfinished ledger entries or resume flags"
fi
unset _resume_active resume_choice _resume_detail

if ((FR0ST_RESUME == 1)) &&
    ((${#INSTALLER_MOUNTS[@]} > 0 || ${#INSTALLER_MAPPERS[@]} > 0)); then
    resume::verify_mounts
fi

# * Snapshot the pre-stage core function set: the reaper below may only
# * unset functions introduced by stages, never core ones.
FR0ST_STAGE_FUNCS_SNAPSHOT="$(declare -F | awk '{print $2}')"
declare -A FR0ST_FUNCS_PRESERVE=()

while IFS= read -r fn; do
    FR0ST_FUNCS_PRESERVE[$fn]=1
done <<<"$FR0ST_STAGE_FUNCS_SNAPSHOT"

# --- Installer stage run loop helpers ---

# stage::reap_functions — unset stage-local functions and skip preserved
stage::reap_functions() {
    local fn
    while IFS= read -r fn; do
        if [[ -z ${FR0ST_FUNCS_PRESERVE[$fn]+x} && -z ${_API_PROVIDERS[$fn]+x} ]] &&
            [[ "$fn" != "run_stage" ]]; then
            unset -f "$fn"
            debug_msg "reaped stage-local function: $fn"
        fi
    done < <(declare -F | awk '{print $2}')
    return 0
}

# stage::drop_unused <stage files…> — drop APIs no surviving stage keeps
stage::drop_unused() {
    local file api
    local -A keep_map=()
    local -a apis=()
    for file in "$@"; do
        read -ra apis <<<"${STAGE_APIS_JOURNAL[$file]:-}"
        for api in "${apis[@]}"; do
            keep_map[$api]=1
        done
    done
    for api in "${!_SOURCED_APIS[@]}"; do
        if [[ -z ${keep_map[$api]+x} && "$api" != core.* ]]; then
            module::drop "$api"
            debug_msg "module::drop unused API: $api"
        fi
    done
    return 0
}

# stage::skip_reason <id> <kind> <status> <forced>
#   DONE skips (destructive needs --redo); RUNNING/FAILED resumes in place.
stage::skip_reason() {
    local id="$1" kind="$2" status="$3" forced="$4"
    if [[ "$id" == "$forced" ]]; then
        return 1
    fi
    if [[ "$status" != "DONE" ]]; then
        return 1
    fi
    if [[ "$kind" == "destructive" ]]; then
        debug_msg "SKIPPED (ledger DONE): $id (destructive; needs --redo)"
    else
        debug_msg "SKIPPED (ledger DONE): $id"
    fi
    return 0
}

# stage::record_failure <id> — record <id> unless the trap already did.
stage::record_failure() {
    local id="$1" detail
    detail="$(state_get stages/last_failure)"
    if [[ "$detail" == "$id" || "$detail" == "$id: "* ]]; then
        return 0
    fi
    state_set "stages/last_failure" "$id"
    return 0
}

# stage::dispatch_validation <id> <pre|post> — run the validation hook for a stage
stage::dispatch_validation() {
    local id="$1" mode="$2" vfn api vrc
    [[ -f "$FR0ST_VALIDATION_ROOT/$id.sh" ]] || {
        debug_msg "validation: file missing (mode $mode); skipping"
        return 0
    }
    # shellcheck disable=SC1090
    source "$FR0ST_VALIDATION_ROOT/$id.sh"
    # * Bash function names cannot contain '-', so stage "NN-name" maps
    # * to `validate::NN_name`
    vfn="validate::${id//-/_}"
    if ! declare -F "$vfn" >/dev/null; then
        error_msg "validation file for $id does not define $vfn"
        return 1
    fi
    local -a vapis=()
    read -r -a vapis <<<"${VALIDATE_APIS[*]:-}"
    unset VALIDATE_APIS
    for api in "${vapis[@]}"; do
        module::source "$api"
    done
    set +e
    "$vfn" "$mode" "$TARGET_MNT"
    vrc=$?
    set -e
    unset -f "$vfn"
    if ((vrc != 0)); then
        error_msg "validation $mode failed for stage $id (rc=$vrc)"
        return 1
    fi
    return 0
}

# stage::run_contract <id> — ledger-marked run with retry/abort handling
stage::run_contract() {
    local id="$1"
    local run_rc=0 retry

    if ! stage::dispatch_validation "$id" pre; then
        exit "$EXIT_VALIDATION_FAIL"
    fi

    state::ledger_mark "$id" RUNNING

    while :; do
        (
            _FR0ST_STAGE_ID="$id"
            export _FR0ST_STAGE_ID
            set -euEo pipefail
            trap 'trap::stage_err "${_FR0ST_STAGE_ID}"' ERR
            run_stage
        ) && run_rc=0 || run_rc=$?
        case "$run_rc" in
        "$EXIT_OK")
            break
            ;;
        "$EXIT_RESUME_RECOVERABLE")
            retry=$(ui::choose "Retry stage '$id'?" "Retry" "Abort") || true
            if [[ "$retry" == "Retry" ]]; then
                status_msg "resume: retrying stage $id"
                state::sync
                continue
            fi
            warn_msg "resume declined; leaving target untouched"
            stage::record_failure "$id"
            exit "$EXIT_STAGE_FAIL"
            ;;
        "$EXIT_USER_ABORT" | 130 | 143 | 129)
            exit "$run_rc"
            ;;
        *)
            stage::record_failure "$id"
            exit "$EXIT_STAGE_FAIL"
            ;;
        esac
    done

    state::sync

    if ! stage::dispatch_validation "$id" post; then
        exit "$EXIT_VALIDATION_FAIL"
    fi

    state::ledger_mark "$id" DONE
    state_set "stages/last_failure" ""
    unset -f run_stage
    return 0
}

# --- Core installer stage run loop ---
status_msg "Running installer stages: $INSTALLER_ROOT/stages"

# ? Collect all APIs before starting stage execution or collect APIs on demand
# ? before each stage execution?
# ? If we are actually going to collect all APIs before starting stage execution
# ? why are we not collecting validation APIs as well?
# ? Merits and demerits of each approach should be noted and decided
# --- Collect each stage's API list once before starting the execution loop ---
declare -A STAGE_APIS_JOURNAL=()
for stage_file in "${STAGE_FILES[@]}"; do
    STAGE_APIS_JOURNAL[$stage_file]="$(stage::apis_of "$stage_file")"
done

forced_stage="$FR0ST_REDO_STAGE"
[[ -z "$forced_stage" ]] && forced_stage="$FR0ST_ONLY_STAGE"

for stage_file in "${STAGE_FILES[@]}"; do
    IFS='|' read -r stage_id stage_kind stage_desc < <(stage::metadata_of "$stage_file")
    if [[ -z "$stage_id" ]]; then
        error_msg "stage file carries no STAGE_ID header: $stage_file"
        exit "$EXIT_INTERNAL"
    fi

    if [[ -n "$FR0ST_RESUME_FROM" && "$stage_id" != "$FR0ST_RESUME_FROM" ]] &&
        [[ "$stage_id" < "$FR0ST_RESUME_FROM" ]]; then
        debug_msg "resume-from: skipped (before $FR0ST_RESUME_FROM): $stage_id"
        continue
    fi

    if [[ -n "$FR0ST_ONLY_STAGE" && "$stage_id" != "$FR0ST_ONLY_STAGE" ]]; then
        debug_msg "skipping unselected stage: $stage_id"
        continue
    fi

    ledger_status="$(state::ledger_status "$stage_id" 2>/dev/null || true)"
    if stage::skip_reason "$stage_id" "$stage_kind" "$ledger_status" "$forced_stage"; then
        continue
    fi

    # * Interrupted destructive stages resume in place: their checkpoints
    # * make re-entry safe; skipping would feed a half-built target.
    if [[ "$stage_kind" == "destructive" && "$stage_id" != "$forced_stage" ]] &&
        [[ "$ledger_status" == "RUNNING" || "$ledger_status" == "FAILED" ]]; then
        status_msg "resume: re-entering interrupted destructive stage $stage_id from ledger checkpoint"
    fi

    debug_msg "Executing stage: $stage_file"

    # shellcheck disable=SC1090
    source "$stage_file"
    if ! declare -F run_stage >/dev/null; then
        error_msg "stage $stage_id is contract-declared but has no run_stage"
        exit "$EXIT_INTERNAL"
    fi

    for api in "${STAGE_APIS[@]:-}"; do
        [[ -n "$api" ]] || continue
        module::source "$api"
    done
    unset STAGE_ID STAGE_KIND STAGE_DESC STAGE_APIS

    stage::run_contract "$stage_id"

    unset _FR0ST_STAGE_ID
    stage::reap_functions
    stage::drop_unused "${STAGE_FILES[@]}"
done

unset stage_file stage_id stage_kind stage_desc ledger_status forced_stage api

# --- Final verification ---
if [[ ${FR0ST_DRYRUN:-0} != "1" && -z "$FR0ST_ONLY_STAGE" ]]; then
    status_msg "Final top-level verification"
    arch-chroot "$TARGET_MNT" findmnt --verify --tab-file /etc/fstab
fi

trace::stop

success_msg "Installation finished."
