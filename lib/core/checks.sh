#!/bin/bash
# Environment assertion helpers.

if [[ ${_SOURCED_core_checks:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_checks="loaded"

module::provide core.checks require_network

# require_network [max_attempts]
require_network() {
    local max_attempts="${1:-3}"
    local attempt=1

    debug_msg "Starting network connectivity check (max attempts: $max_attempts)"
    while ((attempt <= max_attempts)); do
        if curl -fsSL --connect-timeout 5 "https://archlinux.org" >/dev/null 2>&1; then
            debug_msg "Network check succeeded on attempt $attempt"
            debug_msg "Network connectivity confirmed"
            return 0
        fi
        status_msg "Network check attempt $attempt/$max_attempts failed, retrying..."
        ((attempt++))
        sleep 2
    done

    error_msg "No internet connection detected after $max_attempts attempts"
    return 1
}

return 0
