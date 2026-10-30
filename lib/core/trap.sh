#!/bin/bash

# ERR/INT/TERM/HUP handling

if [[ ${_SOURCED_core_trap:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_trap="loaded"

module::provide core.trap trap::install trap::on_err trap::signal trap::stage_err

trap::install() {
    trap 'trap::on_err' ERR
    trap 'trap::signal INT 130' INT
    trap 'trap::signal TERM 143' TERM
    trap 'trap::signal HUP 129' HUP
    debug_msg "trap::install installed orchestrator traps"
    return 0
}

# trap::signal <sig> <code>
trap::signal() {
    local sig="$1" code="$2"
    warn_msg "Received $sig; tearing down and exiting ($code)"
    trace::stop 2>/dev/null || true
    cleanup_target "${TARGET_MNT:-/mnt}"
    trap - INT TERM HUP ERR
    exit "$code"
}

trap::on_err() {
    local rc=$?
    local failed="${BASH_COMMAND:-unknown}"
    local stage="${_FR0ST_STAGE_ID:-unknown}"
    error_msg "Installation failed at stage: $stage"
    error_msg "Failed command: $failed"
    error_msg "Exit code: $rc"
    cleanup_target "${TARGET_MNT:-/mnt}"
    trap - INT TERM HUP ERR
    exit "$rc"
}

trap::stage_err() {
    local rc=$?
    local stage_id="$1"
    local failed="${BASH_COMMAND:-unknown}"
    set +e
    error_msg "Stage '$stage_id' failed on: $failed (rc=$rc)"

    case $rc in
        130 | 143 | 129)
            trace::stop 2>/dev/null || true
            cleanup_target "${TARGET_MNT:-/mnt}"
            exit "$rc"
            ;;
    esac

    state_set "stages/last_failure" "$stage_id: $failed (rc=$rc)" 2>/dev/null || true
    state::ledger_mark "$stage_id" FAILED

    local choice
    choice=$(ui::choose "Stage '$stage_id' failed (rc=$rc). What now?" \
        "Resume: retry this stage (mounts stay)" \
        "Shell: inspect the system, then decide" \
        "Abort: tear down and exit")
    choice="${choice:-abort}"
    case "$choice" in
        Resume*)
            status_msg "Leaving mounts and mappers open; stage $stage_id will be retried"
            exit "$EXIT_RESUME_RECOVERABLE"
            ;;
        Shell*)
            warn_msg "Dropping to a shell for forensics; 'exit' returns to this prompt"
            bash --noprofile --norc -i
            trap::stage_err "$stage_id"
            return 0
            ;;
        *)
            warn_msg "Aborting: tearing down mounted filesystems and mappers"
            trace::stop 2>/dev/null || true
            cleanup_target "${TARGET_MNT:-/mnt}"
            exit "$EXIT_USER_ABORT"
            ;;
    esac
}

return 0
