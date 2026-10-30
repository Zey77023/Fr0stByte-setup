#!/bin/bash

# defaults.conf loader + key registry

if [[ ${_SOURCED_core_config:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_config="loaded"

module::provide core.config defaults::load defaults::profile_load defaults::get defaults::set defaults::check

# Registry of known keys and their shipped defaults.
# config/defaults.conf must stay in sync; unknown keys fail on load.
declare -gA _GLOBAL_DEFAULT_KEYS=() _DEFAULTS=()
_GLOBAL_DEFAULT_KEYS=(
    [low_ram_continue]="no"
    [defaults_layout]=""
    [defaults_locale]=""
    [defaults_timezone]=""
    [fonts_install]="no"
    [diagnostics_install]="no"
    [snap_pac]="yes"
    [luks_header_backup]="yes"
    [perf_swappiness]="no"
    [perf_page_cluster]="no"
    [perf_bbr]="no"
    [perf_trim]="yes"
    [perf_low_latency_audio]="no"
    [perf_journald_limits]="no"
    [hybrid_sleep_delay]="15min"
)

# Parse a key=value file into the target registry.
#   config::__parse <file> <registry_ref>
config::__parse() {
    local file="$1" line key value
    [[ -f $file ]] || {
        error_msg "config file does not exist: $file"
        return 1
    }
    local -n reg="$2"
    while IFS= read -r line || [[ -n $line ]]; do
        # trim whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z $line || $line == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ ! $key =~ ^[a-z_][a-z0-9_]*$ ]]; then
            error_msg "Invalid config key: '${key}' in $file"
            return 1
        fi
        # Quoted key subscript: unquoted `[ $key ]` reads as arithmetic
        # context to the shellcheck gate (SC2004); quoting keeps the key
        # a string without changing registry semantics.
        reg["$key"]="$value"
    done <"$file"
    return 0
}

# defaults:load - Load config/defaults.conf.
defaults::load() {
    local file="${1:-$INSTALLER_ROOT/config/defaults.conf}"
    local unknown_keys
    # NOTE: plain `_DEFAULTS=()` would drop the associative attribute.
    unset _DEFAULTS
    declare -gA _DEFAULTS=()
    config::__parse "$file" _DEFAULTS || return 1
    unknown_keys=$(defaults::check) || {
        error_msg "Unknown keys in $file: $unknown_keys"
        return 1
    }
    debug_msg "Loaded ${#_DEFAULTS[@]} default values from $file"
    return 0
}

# defaults:profile_load - Load a --profile override file on top of the loaded defaults.
defaults::profile_load() {
    local file="$1" key
    declare -gA _PROFILE_PENDING=()
    config::__parse "$file" _PROFILE_PENDING || {
        unset _PROFILE_PENDING
        return 1
    }
    for key in "${!_PROFILE_PENDING[@]}"; do
        _DEFAULTS[$key]=${_PROFILE_PENDING[$key]}
    done
    unset _PROFILE_PENDING
    debug_msg "Profile overrides loaded from $file"
    return 0
}

# defaults::check - List file keys that are not in the registry.
defaults::check() {
    local key collisions=""
    for key in "${!_DEFAULTS[@]}"; do
        if [[ -z ${_GLOBAL_DEFAULT_KEYS[$key]+x} ]]; then
            collisions+="$key "
        fi
    done
    if [[ -n $collisions ]]; then
        printf '%s' "$collisions"
        return 1
    else
        printf '' && return 0
    fi
}

# defaults::get - Get a key from the registry.
defaults::get() {
    local key="$1"
    if [[ -n ${_DEFAULTS[$key]+x} ]]; then
        debug_msg "profile: $key=${_DEFAULTS[$key]}"
        printf '%s\n' "${_DEFAULTS[$key]}"
        return 0
    fi
    if [[ -n ${_GLOBAL_DEFAULT_KEYS[$key]+x} ]]; then
        debug_msg "profile: $key=${_GLOBAL_DEFAULT_KEYS[$key]} (implicit)"
        printf '%s\n' "${_GLOBAL_DEFAULT_KEYS[$key]}"
        return 0
    fi
    error_msg "Unknown defaults key: $key"
    return 1
}

# defaults::get - Check if a key exists in the registry.
defaults::has() {
    [[ -n ${_DEFAULTS[$1]+x} ]] || return 1
}

# defaults::set - Set a registry key to the specified value.
defaults::set() {
    _DEFAULTS[$1]="$2"
}

return 0
