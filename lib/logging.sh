#!/bin/bash
# Logging helpers

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

# Debug logging - logs to file only, not to screen
debug_msg() {
    _log "[DEBUG] $1"
}

status_msg()  {
    if _has_gum; then
        gum style --foreground 212 "[STATUS] $1"
    else
        printf "${_COLOR_BLUE}[STATUS] %s${_COLOR_RESET}\n" "$1"
    fi
    _log "[STATUS] $1"
}

success_msg() {
    if _has_gum; then
        gum style --foreground 82 "[SUCCESS] $1"
    else
        printf "${_COLOR_GREEN}[SUCCESS] %s${_COLOR_RESET}\n" "$1"
    fi
    _log "[SUCCESS] $1"
}

error_msg() {
    if _has_gum; then
        gum style --foreground 196 "[ERROR] $1" >&2
    else
        printf "${_COLOR_RED}[ERROR] %s${_COLOR_RESET}\n" "$1" >&2
    fi
    _log "[ERROR] $1"
}

warn_msg() {
    if _has_gum; then
        gum style --foreground 214 "[WARNING] $1" >&2
    else
        printf "${_COLOR_YELLOW}[WARNING] %s${_COLOR_RESET}\n" "$1" >&2
    fi
    _log "[WARNING] $1"
}
