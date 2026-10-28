#!/bin/bash

# validation/13-limine
# pre: luks uuid and swapfile
# post: state limine/configured, the /etc/default/limine cmdline carries the LUKS uuid + resume_offset,
# the hidden-menu configuration in /boot/limine.conf, and EFI payloads

VALIDATE_APIS=(validation.core.check core.state config.limine)

validate::13_limine() {
    local mode="$1" mnt="${2:-}"
    local conf="$mnt/etc/default/limine"

    case "$mode" in
        pre)
            check::require_state "luks/uuid" "13-limine" || return 1
            check::require_state "swap/file" "13-limine" || return 1
            if check::is_dryrun; then
                debug_msg "validation 13 pre: dry-run; live pickups skipped"
                return 0
            fi
            check::require_file "$mnt$(state_get swap/file "")" || return 1
            ;;
        post)
            check::require_state "limine/configured" "13-limine" || return 1
            if check::is_dryrun; then
                debug_msg "validation 13 post: dry-run; conf/payload assertions skipped"
                return 0
            fi
            if ! grep -q '^TARGET_OS_NAME="Fr0stByte"' "$conf"; then
                check::fail "limine cmdline stub missing TARGET_OS_NAME: $conf"
                return 1
            fi
            local st_uuid
            st_uuid="$(state_get luks/uuid "")"
            if ! grep -Fq "rd.luks.name=${st_uuid}=" "$conf"; then
                check::fail "limine cmdline lacks the LUKS uuid mapping: $conf"
                return 1
            fi
            if ! grep -q '^KERNEL_CMDLINE\[default\]+=".*resume_offset=' "$conf"; then
                check::fail "limine cmdline lacks resume_offset: $conf"
                return 1
            fi
            if ! grep -qx 'timeout: 1' "$mnt/boot/limine.conf" \
                || ! grep -qx 'quiet: yes' "$mnt/boot/limine.conf"; then
                check::fail "hidden-menu directives missing from $mnt/boot/limine.conf"
                return 1
            fi
            limine::assert_assets "$mnt" || return 1
            ;;
        *)
            error_msg "validation 13: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
