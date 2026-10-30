#!/bin/bash
# Package-list parsing: load one-per-line lists into an array via
# nameref; no global PKGS.

if [[ ${_SOURCED_pkg_lists:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_pkg_lists="loaded"

module::provide pkg.lists lists::load

# lists::load <listfile> <out_array_ref>
#   Parses "one package per line" with blank/# comment skipping, name
#   validation (^[a-zA-Z0-9][a-zA-Z0-9@._+:-]*$) and deduplication. rc 1 on a
#   missing file or an invalid entry.
lists::load() {
    local list_file="$1"
    local -n out_pkgs="$2"
    local line package
    local -A seen=()

    debug_msg "Loading package list from: $list_file"
    [[ -f "$list_file" ]] || {
        error_msg "Package list does not exist: $list_file"
        return 1
    }

    out_pkgs=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        package="${line%%[[:space:]]*}"
        [[ "$package" == "$line" && "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9@._+:-]*$ ]] || {
            error_msg "Invalid package name in $list_file: $line"
            return 1
        }
        [[ ${seen[$package]+x} ]] && continue
        seen[$package]=1
        out_pkgs+=("$package")
    done <"$list_file"

    debug_msg "Loaded ${#out_pkgs[@]} packages: ${out_pkgs[*]}"
    return 0
}

return 0
