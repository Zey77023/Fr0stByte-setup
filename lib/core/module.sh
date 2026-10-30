#!/bin/bash
# Module mechanism: the import system for lib APIs and validations.

if [[ ${_SOURCED_core_module:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_module="loaded"

declare -gA _API_PROVIDERS=() _SOURCED_APIS=()

# Register the functions exported by an API module.
#   module::provide <api-name> <func…>
module::provide() {
    local api="$1"
    shift
    local fn
    for fn in "$@"; do
        _API_PROVIDERS[$fn]="$api"
    done
    return 0
}

# Resolve an API name of the form "<category>.<module>" to its file path.
module::path() {
    local api="$1" category="module"
    category="${api%%.*}"
    local name="$api"
    name="${api#*.}"
    local root="$FR0ST_LIB_ROOT"
    if [[ "$category" == "validation" ]]; then
        root="${FR0ST_VALIDATION_ROOT:-$FR0ST_LIB_ROOT/validation}"
        name="${name//./\/}"
        printf '%s/%s.sh' "$root" "$name"
        return 0
    fi
    [[ -n $root ]] || {
        echo "module: FR0ST_LIB_ROOT is not set" >&2
        return 1
    }
    printf '%s/%s/%s.sh' "$root" "$category" "$name"
}

# Source an API module exactly once; idempotent by the sourced-registry.
module::source() {
    local api="$1" path
    if [[ -n ${_SOURCED_APIS[$api]:-} ]]; then
        return 0
    fi
    path=$(module::path "$api") || return 1
    [[ -f "$path" ]] || {
        echo "module: API not found: $api (no file at $path)" >&2
        return 1
    }
    # shellcheck disable=SC1090
    source "$path" || {
        echo "module: failed to source API: $api (at $path)" >&2
        return 1
    }
    _SOURCED_APIS[$api]="loaded"
    return 0
}

# Unload an API module: remove its functions and registry entries.
module::drop() {
    local api="$1" fn
    for fn in "${!_API_PROVIDERS[@]}"; do
        if [[ ${_API_PROVIDERS[$fn]} == "$api" ]]; then
            unset -f "$fn" 2>/dev/null || true
            unset "_API_PROVIDERS[$fn]"
        fi
    done
    unset "_SOURCED_APIS[$api]" 2>/dev/null
    return 0
}

return 0
