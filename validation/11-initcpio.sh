#!/bin/bash

# validation/11-initcpio
# pre : the target has mkinitcpio.conf
# post : state initramfs/done, the conf carries the expected data, the
# microcode package+image check holds, and mkinitcpio produced images.

VALIDATE_APIS=(
    validation.core.check
    core.state
    system.chroot
    config.initramfs
    system.detect
    pkg.pacman
)

validate::11_initcpio() {
    local mode="$1" mnt="${2:-}"
    local conf="$mnt/etc/mkinitcpio.conf"

    case "$mode" in
        pre)
            if check::is_dryrun; then
                debug_msg "validation 11 pre: dry-run; conf check skipped"
                return 0
            fi
            check::require_file "$conf" || return 1
            ;;
        post)
            check::require_state "initramfs/done" "11-initcpio" || return 1
            if check::is_dryrun; then
                debug_msg "validation 11 post: dry-run; conf/image assertions skipped"
                return 0
            fi
            if ! initramfs::__has_token "$conf" MODULES btrfs; then
                check::fail "MODULES does not contain btrfs"
                return 1
            fi
            if ! initramfs::__has_token "$conf" BINARIES /usr/bin/btrfs; then
                check::fail "BINARIES does not contain /usr/bin/btrfs"
                return 1
            fi
            if ! initramfs::__has_token "$conf" HOOKS sd-encrypt; then
                check::fail "HOOKS does not contain sd-encrypt"
                return 1
            fi
            if ! initramfs::__has_token "$conf" HOOKS resume; then
                check::fail "HOOKS does not contain resume"
                return 1
            fi

            local st_pkg st_img
            detect::microcode_pkg st_pkg || return 1
            if ! pkg::is_installed "$mnt" "$st_pkg"; then
                check::fail "microcode package $st_pkg missing from target"
                return 1
            fi
            detect::microcode_img st_img || return 1
            check::require_file "$mnt$st_img" || return 1
            initramfs::assert_images "$mnt" || return 1
            ;;
        *)
            error_msg "validation 11: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
