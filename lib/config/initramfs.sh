#!/bin/bash

# mkinitcpio configuration: idempotent mkinitcpio logic to add correct binaries,
# and hooks for btrfs, encryption and hibernation.

if [[ ${_SOURCED_config_initramfs:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_initramfs="loaded"

declare -g _INITRAMFS_CONFIGURED=""

module::provide config.initramfs initramfs::configure initramfs::rebuild initramfs::assert_images

# initramfs::__has_token <conf> <section> <item>
#   <item> must sit inside ${section}=(…) surrounded
#   by '(' ')' or whitespace.
initramfs::__has_token() {
    # NOTE: grep with regular expressions will escape the characters that would otherwise need to be
    # NOTE: treated as is, so the long escape block escapes all those before giving it to grep
    local conf="$1" section="$2" item="$3" esc
    esc="${item//\\/\\\\}"
    esc="${esc//./\\.}"
    esc="${esc//\*/\\*}"
    esc="${esc//\+/\\+}"
    esc="${esc//\?/\\?}"
    esc="${esc//[/\\[}"
    esc="${esc//]/\\]}"
    esc="${esc//(/\\(}"
    esc="${esc//)/\\)}"
    esc="${esc//|/\\|}"
    esc="${esc//\$/\\\$}"
    esc="${esc//\^/\\^}"
    grep -Eq "^${section}=.*(\(|[[:space:]])${esc}([[:space:]]|\))" \
        "$conf" 2>/dev/null
}

# initramfs::__append_line <conf> <line> — append a line to the configuration file.
initramfs::__append_line() {
    exec_cmd sh -c "printf '%s\n' '$2' >> '$1'"
}

# initramfs::__ensure_tokens <file> <section> <item…>
#   Adds a token to SECTION=(…) once; creates the section line when absent.
initramfs::__ensure_tokens() {
    local conf="$1" section="$2"
    shift 2
    local item
    local -a add=()
    for item in "$@"; do
        [[ -n "$item" ]] || continue
        if initramfs::__has_token "$conf" "$section" "$item"; then
            debug_msg "'${item}' already present in ${section}"
        else
            add+=("$item")
        fi
    done
    ((${#add[@]} > 0)) || return 0
    local joined="${add[*]}"
    if grep -q "^${section}=" "$conf" 2>/dev/null; then
        exec_cmd sed -i "s|^${section}=(|${section}=(${joined} |" "$conf" \
            || return 1
    else
        initramfs::__append_line "$conf" "${section}=(${joined})" || return 1
    fi
    return 0
}

# initramfs::configure <mnt> <modules_ref> <binaries_ref> <hooks_ref>
# configure initramfs file with the ref arrays.
initramfs::configure() {
    local mnt="$1"
    local conf="$mnt/etc/mkinitcpio.conf"
    local -n modules="$2"
    local -n binaries="$3"
    local -n hooks="$4"

    if [[ ! -f "$conf" ]]; then
        if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
            debug_msg "DRY-RUN: mkinitcpio.conf absent; token additions journal-only"
        else
            error_msg "mkinitcpio.conf missing in target: $conf"
            return 1
        fi
    fi

    if [[ ${_INITRAMFS_CONFIGURED:-} != "$conf" ]]; then
        exec_cmd cp "$conf" "$conf.bak"
        _INITRAMFS_CONFIGURED="$conf"
    fi

    initramfs::__ensure_tokens "$conf" MODULES "${modules[@]}" || return 1
    initramfs::__ensure_tokens "$conf" BINARIES "${binaries[@]}" || return 1

    local hook
    for hook in "${hooks[@]}"; do
        [[ -n "$hook" ]] || continue
        if initramfs::__has_token "$conf" HOOKS "$hook"; then
            debug_msg "hooks: '${hook}' already present"
            continue
        fi
        # Hook ordering: sd-encrypt -> right after 'block',
        # resume -> right after 'sd-encrypt', anything else
        # -> before 'filesystems'
        case "$hook" in
            sd-encrypt)
                exec_cmd sed -i -E \
                    's/^([[:space:]]*HOOKS=.*\bblock\b)(.*\bfilesystems\b.*)$/\1 sd-encrypt\2/' \
                    "$conf" || return 1
                ;;
            resume)
                exec_cmd sed -i -E \
                    's/^([[:space:]]*HOOKS=.*\bsd-encrypt\b)(.*\bfilesystems\b.*)$/\1 resume\2/' \
                    "$conf" || return 1
                ;;
            *)
                exec_cmd sed -i -E \
                    "s/^([[:space:]]*HOOKS=.*)(\bfilesystems\b.*)$/\1 ${hook} \2/" \
                    "$conf" || return 1
                ;;
        esac
        if ! initramfs::__has_token "$conf" HOOKS "$hook"; then
            initramfs::__append_line "$conf" \
                'HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block sd-encrypt resume filesystems fsck)'
        fi
        debug_msg "hooks: ensured '${hook}' in HOOKS"
    done
    return 0
}

# initramfs::rebuild <mnt> — mkinitcpio -P inside spin.
initramfs::rebuild() {
    ui::spin "Regenerating initramfs..." -- chroot_exec "$1" -- mkinitcpio -P
}

# initramfs::assert_images <mnt> — at least one initramfs image in /boot.
initramfs::assert_images() {
    local mnt="$1" count
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: assuming mkinitcpio produced images in $mnt/boot"
        return 0
    fi
    count=$(find "$mnt/boot" -maxdepth 1 -type f -name 'initramfs-*.img' -printf '.' 2>/dev/null | wc -c)
    ((count > 0)) || {
        error_msg "No initramfs image found in $mnt/boot"
        return 1
    }
    return 0
}

return 0
