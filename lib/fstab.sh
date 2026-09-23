#!/bin/bash

ensure_fstab_entry() {
    local fstab="$1" source="$2" target="$3" fstype="$4" options="$5" dump="$6" pass="$7"
    local temporary

    [[ -f "$fstab" ]] || : >"$fstab"
    temporary=$(mktemp "${fstab}.XXXXXX")

    awk -v source="$source" -v target="$target" -v fstype="$fstype" \
        '$0 ~ /^[[:space:]]*#/ || NF < 3 { print; next }
         !($1 == source && $2 == target && $3 == fstype) { print }' \
        "$fstab" >"$temporary"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$source" "$target" "$fstype" "$options" "$dump" "$pass" >>"$temporary"
    mv -- "$temporary" "$fstab"
}

fstab_entry_count() {
    local fstab="$1" source="$2" target="$3" fstype="$4"

    awk -v source="$source" -v target="$target" -v fstype="$fstype" \
        '$0 !~ /^[[:space:]]*#/ && NF >= 3 && $1 == source && $2 == target && $3 == fstype { count++ }
         END { print count + 0 }' "$fstab"
}
