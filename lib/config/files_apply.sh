#!/bin/bash

# Asset deployment
#
# Layout:
#   assets/target/<relpath>        — file mirrored into the target
#   assets/permissions             — per line "<mode>\t<relpath>" for each file

if [[ ${_SOURCED_config_files_apply:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_files_apply="loaded"

module::provide config.files_apply files_apply::apply

files_apply::__assets_root() {
    printf '%s\n' "${FR0ST_ASSETS_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/assets}"
}

# files_apply::__mode_of <relpath> <out_var>
files_apply::__mode_of() {
    local rel="$1"
    local -n out_mode="$2"
    out_mode="0644"
    if [[ -f $_FRA_PERMISSIONS ]]; then
        local row_mode row_line
        while IFS=$'\t' read -r row_mode row_line; do
            if [[ "$row_line" == "$rel" ]]; then
                out_mode="$row_mode"
                break
            fi
        done <"$_FRA_PERMISSIONS"
    fi
    return 0
}

# files_apply::apply <mnt> [--only <relpath…>]
files_apply::apply() {
    local mnt="$1"
    shift

    local only_mode=0
    local -a only=() rels=()
    local arg rel mode
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only)
                only_mode=1
                shift
                ;;
            *)
                only+=("$1")
                shift
                ;;
        esac
    done
    if ((only_mode == 0)); then
        only=()
    fi

    local assets_root
    assets_root="$(files_apply::__assets_root)"
    _FRA_PERMISSIONS="$assets_root/permissions"
    [[ -d "$assets_root/target" ]] || {
        debug_msg "files_apply: no asset tree at $assets_root/target"
        return 0
    }

    mapfile -t rels < <(find "$assets_root/target" -type f -printf '%P\n')
    ((${#rels[@]} > 0)) || return 0

    for rel in "${rels[@]}"; do
        if ((only_mode == 1)); then
            local found=0 rel_candidate
            for rel_candidate in "${only[@]}"; do
                [[ "$rel_candidate" == "$rel" ]] && found=1 && break
            done
            if ((found == 0)); then
                continue
            fi
        fi
        files_apply::__mode_of "$rel" mode
        exec_cmd install -D -m "$mode" "$assets_root/target/$rel" "$mnt/$rel" || {
            error_msg "files_apply: failed to deploy $rel"
            return 1
        }
        debug_msg "files_apply: deployed $rel (mode $mode)"
    done
    return 0
}

return 0
