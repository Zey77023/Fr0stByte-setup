#!/bin/bash

request_password() {
    local label="$1" pass confirm tries=3 n=0
    debug_msg "Requesting password for: $label"

    while ((n < tries)); do
        pass=$(gum input --password --placeholder "Enter $label password")
        if [[ -z "$pass" ]]; then
            error_msg "Password cannot be empty"
            ((n++)); continue
        fi
        confirm=$(gum input --password --placeholder "Confirm $label password")
        if [[ "$pass" != "$confirm" ]]; then
            error_msg "Passwords do not match"
            ((n++)); continue
        fi
        debug_msg "Password for $label accepted"
        echo "$pass"
        return 0
    done

    error_msg "Too many failed attempts"
    return 1
}
