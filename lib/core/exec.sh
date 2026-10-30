#!/bin/bash

# Any command that runs in the installer should be routed through exec_cmd.

if [[ ${_SOURCED_core_exec:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_exec="loaded"

module::provide core.exec exec_cmd

exec::record() {
    if [[ -n ${FR0ST_COMMAND_JOURNAL:-} ]]; then
        local line="" a
        for a in "$@"; do
            # TAB is the field separator; flatten tabs/newlines inside an
            # argument so its spaces survive (journal consumers restore
            # them with tr) without breaking the line protocol.
            a="${a//$'\t'/ }"
            a="${a//$'\n'/ }"
            line+="${line:+$'\t'}$a"
        done
        printf '%s\n' "$line" >>"$FR0ST_COMMAND_JOURNAL"
    fi
    return 0
}

exec_cmd() {
    if (( $# == 0 )); then
        error_msg "exec_cmd invoked with no arguments"
        return 1
    fi
    exec::record "$@"
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: would execute: $*"
        return 0
    fi
    "$@"
}

return 0
