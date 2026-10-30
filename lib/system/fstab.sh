#!/bin/bash

# fstab entry management.

if [[ ${_SOURCED_system_fstab:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_system_fstab="loaded"

module::provide system.fstab ensure_fstab_entry fstab_entry_count fstab::swapfile_entry

# ensure_fstab_entry <fstab> <source> <target> <fstype> <options> <dump> <pass>
ensure_fstab_entry() {
    local fstab="$1" source="$2" target="$3" fstype="$4" options="$5" dump="$6" pass="$7"

    # shellcheck disable=SC2016
    exec_cmd sh -c '
        fstab="$1"; source="$2"; target="$3"; fstype="$4"
        options="$5"; dump="$6"; pass="$7"; prog="$8"
        [ -f "$fstab" ] || : >"$fstab" || exit 1
        tmp=$(mktemp "${fstab}.XXXXXX") || exit 1
        awk -v source="$source" -v target="$target" -v fstype="$fstype" \
            "$prog" "$fstab" >"$tmp" || exit 1
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$source" "$target" "$fstype" "$options" "$dump" "$pass" >>"$tmp" || exit 1
        mv "$tmp" "$fstab" || exit 1
    ' sh "$fstab" "$source" "$target" "$fstype" "$options" "$dump" "$pass" \
        '$0 ~ /^[[:space:]]*#/ || NF < 3 { print; next }
         !($2 == target && $3 == fstype) { print }'
}

fstab_entry_count() {
    local fstab="$1" source="$2" target="$3" fstype="$4"

    awk -v source="$source" -v target="$target" -v fstype="$fstype" \
        '$0 !~ /^[[:space:]]*#/ && NF >= 3 && $1 == source && $2 == target && $3 == fstype { count++ }
         END { print count + 0 }' "$fstab"
}

# fstab::swapfile_entry <fstab> <src> <mnt>
fstab::swapfile_entry() {
    ensure_fstab_entry "$1" "$2" "$3" "swap" "defaults,pri=-1" "0" "0"
}

return 0
