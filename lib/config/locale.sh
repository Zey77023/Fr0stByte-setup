#!/bin/bash

# Locale APIs

if [[ ${_SOURCED_config_locale:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_locale="loaded"

module::provide config.locale locale::available locale::locale_set

# locale::available <out_locales_ref> <mnt> — sorted, de-duplicated locale
# names commented/found in the target's locale.gen.
locale::available() {
    local -n out_locales="$1"
    local mnt="$2"
    local locale_gen="$mnt/etc/locale.gen"
    if [[ ! -f "$locale_gen" ]]; then
        if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
            debug_msg "DRY-RUN: no target locale.gen; canned canonical set"
            out_locales=(en_US.UTF-8 de_DE.UTF-8)
            return 0
        fi
        error_msg "No locale.gen in target ($locale_gen missing)"
        return 1
    fi
    mapfile -t out_locales < <(
        awk '/^[#[:space:]]*[a-zA-Z]+_[a-zA-Z]+/ {
            sub(/^[#[:space:]]*/, "", $1);
            print $1
        }' "$locale_gen" | sort -u
    )
    ((${#out_locales[@]} > 0)) || {
        error_msg "No locales found in $locale_gen."
        return 1
    }
    return 0
}

# locale::locale_set <mnt> <selected_ref> <default_lang> <keyboard_layout>
#   selected_ref is an array NAME of already-chosen locales.
#   Re-comments all locale entries, uncomments the chosen ones, runs locale-gen, writes
#   locale.conf and vconsole.conf.
locale::locale_set() {
    local mnt="$1"
    local -n selected="$2"
    local default_lang="$3"
    local keyboard_layout="$4"
    local locale_gen="$mnt/etc/locale.gen"
    local loc

    if [[ ! -f "$locale_gen" && ${FR0ST_DRYRUN:-0} != "1" ]]; then
        error_msg "locale.gen missing in target: $locale_gen"
        return 1
    fi

    # Re-comment all UTF-8 locales, then uncomment only the selected ones
    # (idempotent: a second run produces the same file).
    exec_cmd sed -i -E \
        's/^([[:space:]]*)([A-Za-z0-9_\.@-]+[[:space:]]+[A-Za-z0-9_\.-]+)/#\1\2/' \
        "$locale_gen" || return 1
    for loc in "${selected[@]}"; do
        exec_cmd sed -i -E \
            "s/^[#[:space:]]*(${loc}[[:space:]]+[A-Za-z0-9_\.-]+.*)/\1/" \
            "$locale_gen" || return 1
    done

    if ! ui::spin "Regenerating locales in target..." -- \
        chroot_exec "$mnt" -- locale-gen; then
        return 1
    fi

    exec_cmd tee "$mnt/etc/locale.conf" >/dev/null <<EOS
LANG=$default_lang
EOS

    if [[ -n "$keyboard_layout" ]]; then
        exec_cmd tee "$mnt/etc/vconsole.conf" >/dev/null <<EOS
KEYMAP=$keyboard_layout
EOS
    fi
    return 0
}

return 0
