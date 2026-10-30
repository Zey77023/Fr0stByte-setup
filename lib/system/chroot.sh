#!/bin/bash

# chroot command execution.

if [[ ${_SOURCED_system_chroot:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_system_chroot="loaded"

module::provide system.chroot chroot_exec

#   chroot_exec <mnt> [--expect "0 1"] [--code <nameref>] -- cmd…
#     - rc 0 iff the exit code is in the expect set (default "0"), else rc 1
chroot_exec() {
    local mnt="$1"
    shift
    local -a expect_codes=(0)
    local code_var="" expect_set=0
    local -a cmd=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --expect)
                [[ $expect_set -eq 0 ]] || {
                    error_msg "chroot_exec: --expect given twice"
                    return 1
                }
                shift
                IFS=' ' read -ra expect_codes <<<"$1"
                expect_set=1
                shift
                ;;
            --code)
                shift
                code_var="$1"
                shift
                ;;
            --)
                shift
                cmd=("$@")
                break
                ;;
            *)
                cmd=("$@")
                break
                ;;
        esac
    done

    ((${#cmd[@]} > 0)) || {
        error_msg "chroot_exec: no command given"
        return 1
    }

    debug_msg "Executing in chroot($mnt): ${cmd[*]}"
    debug_msg "Expected exit codes: ${expect_codes[*]}"

    set +e
    exec_cmd arch-chroot "$mnt" "${cmd[@]}"
    local exit_code=$?
    set -e
    debug_msg "Chroot command exited with code: $exit_code"

    if [[ -n "$code_var" ]]; then
        local -n rc_ref="$code_var"
        rc_ref="$exit_code"
    fi

    local expect_code
    for expect_code in "${expect_codes[@]}"; do
        if [[ "$exit_code" == "$expect_code" ]]; then
            return 0
        fi
    done

    error_msg "chroot failed (exit $exit_code): ${cmd[*]}"
    return 1
}

return 0
