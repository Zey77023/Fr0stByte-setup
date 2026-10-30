#!/bin/bash

# UI wrappers with plain fallbacks

# TODO: UI functions should not directly accept gum args;
# TODO: they should accept a structured set of options and translate them to gum args internally.

if [[ ${_SOURCED_core_ui:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_ui="loaded"

module::provide core.ui ui::spin ui::confirm ui::choose ui::filter ui::input

# ui::spin <title> -- cmd…
ui::spin() {
    local title="$1"
    shift
    if (( $# == 0 )) || [[ "$1" != "--" ]]; then
        error_msg "ui::spin expects a title followed by -- cmd…"
        return 1
    fi
    shift
    exec::record "$@"
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: spin $title :: $*"
        return 0
    fi
    if _has_gum && [[ "$(type -t "$1")" == "file" ]]; then
        gum spin --title "$title" -- "$@"
    else
        status_msg "$title"
        "$@"
    fi
}

# ui::confirm <key> <prompt> [yes|no]
# Autodetects answers from defaults conf
ui::confirm() {
    local key="$1" prompt="$2" default="${3:-no}"
    if defaults::has "$key"; then
        local value
        value=$(defaults::get "$key")
        status_msg "profile: $key=$value (configured)"
        [[ "$value" == "yes" ]] || return 1
        return 0
    fi
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: auto-answer confirm '$key' => $default"
        [[ "$default" == "yes" ]] || return 1
        return 0
    fi
    if _has_gum; then
        gum confirm "$prompt" --default="$default"
    else
        read -r -p "$prompt [y/N] " reply
        [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
    fi
}

# Plain numbered chooser used by choose/filter fallbacks.
#   ui::__select <header> <single|multi> <choice…>
ui::__select() {
    local header="$1" mode="$2"
    shift 2
    local -a items=("$@")
    local i item selected reply
    status_msg "$header"
    for i in "${!items[@]}"; do
        printf '%d) %s\n' "$((i + 1))" "${items[$i]}"
    done
    if [[ "$mode" == "multi" ]]; then
        read -r -p "Numbers (separated by space/comma; empty = cancel): " reply
        if [[ -z "${reply// }" ]]; then
            return 1
        fi
        reply="${reply//,/ }"
        for item in $reply; do
            if [[ "$item" =~ ^[0-9]+$ ]] && ((item >= 1 && item <= ${#items[@]})); then
                printf '%s\n' "${items[item - 1]}"
            fi
        done
        return 0
    fi
    read -r -p "Number (empty = cancel): " reply
    if [[ ! "$reply" =~ ^[0-9]+$ ]] || ((reply < 1 || reply > ${#items[@]})); then
        return 1
    fi
    printf '%s\n' "${items[reply - 1]}"
}

# ui::choose <header> <choices…>
ui::choose() {
    local header="$1"
    shift
    local choice
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]] || _has_gum; then
        choice=$(gum choose --header="$header" "$@") || choice=""
    else
        choice=$(ui::__select "$header" single "$@") || choice=""
    fi
    debug_msg "ui::choose [$header] => ${choice:-<cancelled>}"
    printf '%s\n' "$choice"
}

# ui::filter <gum-filter args…>  (stdin in, stdout filtered)
ui::filter() {
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: ui::filter (FakeUI feeds the pipe)"
    fi
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]] || _has_gum; then
        gum filter "$@"
        return 0
    fi
    if [[ "$*" == *--no-limit* ]]; then
        warn_msg "ui::filter: gum unavailable - multi-select degraded to a single choice"
    else
        status_msg "gum not available: passing the first input line through"
    fi
    head -n1
    return 0
}

# ui::input <gum-input args…>  (prompts, echoes value)
ui::input() {
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: ui::input (FakeUI mocks gum input)"
    fi
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]] || _has_gum; then
        gum input "$@"
        return 0
    fi
    local placeholder=""
    if [[ "$*" == *--placeholder\ * ]]; then
        placeholder="${*##*--placeholder }"
    fi
    read -r -p "${placeholder:-value}: " REPLY
    printf '%s\n' "$REPLY"
}

return 0
