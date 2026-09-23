#!/bin/bash

chroot_exec() {
    local expect_codes=(0) cmd=() arg

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --expect)
                shift
                IFS=' ' read -ra expect_codes <<< "$1"
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

    debug_msg "Executing in chroot: ${cmd[*]}"
    debug_msg "Expected exit codes: ${expect_codes[*]}"

    set +e
    arch-chroot "$TARGET_MNT" "${cmd[@]}"
    local exit_code=$?
    set -e

    debug_msg "Chroot command exited with code: $exit_code"

    local expected=0
    for code in "${expect_codes[@]}"; do
        if [[ $exit_code -eq $code ]]; then
            expected=1
            break
        fi
    done

    if [[ $expected -eq 0 ]]; then
        error_msg "chroot failed (exit $exit_code): ${cmd[*]}"
        exit 1
    fi

    CHROOT_EXEC_EXIT_CODE=$exit_code
    return 0
}
