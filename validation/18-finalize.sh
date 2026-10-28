#!/bin/bash

# validation/18-finalize —
# pre: luks/uuid, partition/root, swap/file must all be present and mactch the state of target;
# valid fstab, initramfs and snapshots subvol
# post: nothing to assert after installation is finished

VALIDATE_APIS=(validation.core.check core.state system.chroot system.fstab)

validate::18_finalize() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            check::assert_state_keys "luks/uuid" "partition/root" "swap/file" \
                "18-finalize" || return 1
            if check::is_dryrun; then
                debug_msg "validation 18 pre: dry-run; final storage/boot assertions skipped"
                return 0
            fi

            check::assert_command_succeeded "$mnt" findmnt --verify --tab-file /etc/fstab \
                || return 1

            cryptsetup luksDump "$(state_get partition/root "")" >/dev/null || {
                check::fail "cryptsetup could not dump the root LUKS container"
                return 1
            }

            if ! (( "$(fstab_entry_count "$mnt/etc/fstab" \
                "$(state_get swap/file "")" "none" "swap")" == 1 )); then
                check::fail "final fstab verification found an invalid swapfile entry: $mnt/etc/fstab"
                return 1
            fi

            [[ -s "$mnt/etc/default/limine" ]] || {
                check::fail "Limine configuration is missing from the installed system"
                return 1
            }
            grep -Eq 'resume=/dev/mapper/[^ ]+ resume_offset=[1-9][0-9]*' \
                "$mnt/etc/default/limine" || {
                check::fail "Limine configuration has no valid hibernation resume parameters"
                return 1
            }

            find "$mnt/boot" -maxdepth 1 -type f -name 'initramfs-*.img' \
                -print -quit 2>/dev/null | grep -q . || {
                check::fail "No initramfs image found in the target boot directory"
                return 1
            }

            local source
            source="$(findmnt -n -o SOURCE -T "$mnt/.snapshots" 2>/dev/null || true)"
            [[ "$source" == *"@snapshots"* ]] || {
                check::fail "Final /.snapshots mount is not backed by @snapshots: ${source:-<none>}"
                return 1
            }
            ;;
        post)
            debug_msg "validation 18 post: summary/prompt stage — nothing to assert"
            ;;
        *)
            error_msg "validation 18: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
