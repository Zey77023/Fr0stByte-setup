#!/bin/bash

require_paths() {
    debug_msg "Checking required paths..."
    local p
    for p in "$@"; do
        if [[ ! -e "$p" ]]; then
            error_msg "Missing: $p"
            exit 1
        fi
        debug_msg "Found: $p"
    done
}

require_root() {
    debug_msg "Checking for root privileges..."
    if [[ "$EUID" -ne 0 ]]; then
        error_msg "This installer must be run as root"
        exit 1
    fi
    debug_msg "Confirmed running as root user"
}

check_network() {
    local max_attempts="${1:-3}"
    local attempt=1

    debug_msg "Starting network connectivity check (max attempts: $max_attempts)"
    while ((attempt <= max_attempts)); do
        if curl -fsSL --connect-timeout 5 "https://archlinux.org" > /dev/null 2>&1; then
            debug_msg "Network check succeeded on attempt $attempt"
            return 0
        fi
        status_msg "Network check attempt $attempt/$max_attempts failed, retrying..."
        ((attempt++))
        sleep 2
    done

    error_msg "No internet connection detected after $max_attempts attempts"
    return 1
}

require_network() {
    debug_msg "Checking network connectivity..."
    check_network || { error_msg "Network connection required"; exit 1; }
    debug_msg "Network connectivity confirmed"
}
