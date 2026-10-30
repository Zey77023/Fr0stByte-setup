#!/bin/bash

# Interactive password recording + temporary passfile

if [[ ${_SOURCED_core_secret:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_secret="loaded"

module::provide core.secret secret::request secret::shred secret::scope \
    request_password

# request_password <label> — print a confirmed password to stdout.
#   Up to 3 attempts; returns 1 on cancel/empty/mismatch.
request_password() {
    local label="$1" pass confirm tries=3 n=0
    debug_msg "Requesting password for: $label"

    while ((n < tries)); do
        pass=$(gum input --password --placeholder "Enter $label password") || {
            error_msg "Password prompt cancelled"
            return 1
        }
        if [[ -z "$pass" ]]; then
            error_msg "Password cannot be empty"
            ((n++))
            continue
        fi
        confirm=$(gum input --password --placeholder "Confirm $label password") || {
            error_msg "Password prompt cancelled"
            return 1
        }
        if [[ "$pass" != "$confirm" ]]; then
            error_msg "Passwords do not match"
            ((n++))
            continue
        fi
        debug_msg "Password for $label accepted"
        printf '%s\n' "$pass"
        return 0
    done

    error_msg "Too many failed attempts"
    return 1
}

# secret::request <label> <out_passfile_var>
secret::request() {
    local label="$1"
    local -n passfile_ref="$2"
    local secret_pwd target_path

    if ! secret_pwd=$(request_password "$label"); then
        debug_msg "secret::request cancelled for: $label"
        return 1
    fi
    target_path=$(mktemp) || {
        error_msg "Could not create a passfile"
        unset secret_pwd
        return 1
    }
    chmod 600 "$target_path"
    if ! printf '%s\n' "$secret_pwd" >"$target_path"; then
        error_msg "Could not write the passfile"
        secret::shred "$target_path"
        unset secret_pwd
        return 1
    fi
    unset secret_pwd
    debug_msg "Passfile created for: $label"
    passfile_ref="$target_path"
    return 0
}

# secret::scope <label> -- <cmd…>
secret::scope() {
    local label="$1" passfile="" rc=0
    shift
    [[ "${1:-}" == "--" && $# -gt 1 ]] || {
        error_msg "secret::scope: expected '<label> -- <cmd…>'"
        return 1
    }
    shift
    secret::request "$label" passfile || return 1
    "$@" "$passfile" || rc=$?
    secret::shred "$passfile"
    return "$rc"
}

# Securely delete and unlink a passfile (or any temporary secret file).
secret::shred() {
    local passfile="$1"
    [[ -n "$passfile" && -f "$passfile" ]] || return 0
    shred -u "$passfile" 2>/dev/null || rm -f "$passfile"
    debug_msg "Passfile shredded"
    return 0
}

return 0
