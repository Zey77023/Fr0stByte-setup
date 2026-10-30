#!/bin/bash
# Logging helpers.

if [[ ${_SOURCED_core_logging:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_logging="loaded"

module::provide core.logging _log _has_gum debug_msg status_msg success_msg error_msg warn_msg

_log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
}

# Check if gum is available
_has_gum() {
    command -v gum >/dev/null 2>&1
}

# ANSI color codes for fallback when gum is not available
_COLOR_RESET="\033[0m"
_COLOR_BLUE="\033[38;5;212m"
_COLOR_GREEN="\033[38;5;82m"
_COLOR_RED="\033[38;5;196m"
_COLOR_YELLOW="\033[38;5;214m"

# _emit <label> <fg> <ansi-color> <stdout|stderr> <msg>
_emit() {
    local label="$1" fg="$2" color="$3" stream="$4" msg="$5"
    if _has_gum; then
        if [[ "$stream" == "stderr" ]]; then
            gum style --foreground "$fg" "$label $msg" >&2
        else
            gum style --foreground "$fg" "$label $msg"
        fi
    elif [[ "$stream" == "stderr" ]]; then
        printf '%b%s %s%b\n' "$color" "$label" "$msg" "$_COLOR_RESET" >&2
    else
        printf '%b%s %s%b\n' "$color" "$label" "$msg" "$_COLOR_RESET"
    fi
    _log "$label $msg"
}

# Debug logging - logs to file only
debug_msg() {
    _log "[DEBUG] $1"
}

status_msg() { _emit "[STATUS]" 212 "$_COLOR_BLUE" stdout "$1"; }

success_msg() { _emit "[SUCCESS]" 82 "$_COLOR_GREEN" stdout "$1"; }

error_msg() { _emit "[ERROR]" 196 "$_COLOR_RED" stderr "$1"; }

warn_msg() { _emit "[WARNING]" 214 "$_COLOR_YELLOW" stderr "$1"; }


return 0
