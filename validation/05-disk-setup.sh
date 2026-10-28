#!/bin/bash

# validation/05-disk-setup
#   pre : partition/disk + partition/mode (MANUAL also boot+root);
#         asserts the disk is whole/unmounted/swapless.
#   post: assert all sub step keys are journaled; asserts the physical result
#         (mapper present+readable, filesystems, hierarchy at <mnt>).

VALIDATE_APIS=(validation.core.check core.state core.config)

validate::05_disk_setup() {
    local mode="$1" mnt="${2:-}"
    local disk p_mode luks_name mapper luks_uuid st_boot st_root fs

    case "$mode" in
        pre)
            disk="$(state_get partition/disk)"
            p_mode="$(state_get partition/mode)"
            if [[ -z "$disk" || -z "$p_mode" ]]; then
                check::fail "stage 05 requires partition/disk and partition/mode"
                return 1
            fi
            if [[ "$p_mode" == "MANUAL" ]]; then
                check::require_state "partition/boot" "05-disk-setup" || return 1
                check::require_state "partition/root" "05-disk-setup" || return 1
            fi
            if check::is_dryrun; then
                debug_msg "validation 05 pre: dry-run; disk-state assertions skipped"
                return 0
            fi
            check::assert_whole_disk "$disk" || return 1
            check::assert_no_mounts "$disk" || return 1
            check::assert_no_swap_on "$disk" || return 1
            return 0
            ;;
        post)
            local -a keys=(
                "partition/boot" "partition/root" "luks/name" "luks/uuid"
                "luks/formatted" "luks/opened" "swap/file" "swap/created"
                "mounts/done"
            )
            local key
            for key in "${keys[@]}"; do
                check::require_state "$key" "05-disk-setup" || return 1
            done

            if check::is_dryrun; then
                debug_msg "validation 05 post: dry-run; state assertions done"
                return 0
            fi

            luks_name="$(state_get luks/name)"
            mapper="/dev/mapper/${luks_name}"
            if [[ ! -e "$mapper" ]]; then
                check::fail "expected open LUKS mapper is missing: $mapper"
                return 1
            fi
            fs="$(lsblk -dn -o FSTYPE "$mapper" 2>/dev/null)"
            [[ "$fs" == "btrfs" ]] || {
                check::fail "mapper $mapper is not btrfs (fstype=$fs)"
                return 1
            }
            st_boot="$(state_get partition/boot)"
            fs="$(lsblk -dn -o FSTYPE "$st_boot" 2>/dev/null)"
            [[ "$fs" == "vfat" ]] || {
                check::fail "boot partition $st_boot is not vfat (fstype=$fs)"
                return 1
            }
            luks_uuid=$(state_get luks/uuid)
            if [[ "$luks_uuid" != "$(cryptsetup luksUUID "$(state_get partition/root)")" ]]; then
                check::fail "state luks/uuid does not match the container"
                return 1
            fi
            # The header backup rides on the ESP when the profile enables
            # it; the state key only lands after a successful write.
            if [[ "$(defaults::get luks_header_backup)" == "yes" ]]; then
                local hdr_file
                hdr_file="$(state_get luks/header_backup)"
                if ! [[ -s "$hdr_file" ]]; then
                    check::fail "LUKS header backup missing on the ESP: $hdr_file"
                    return 1
                fi
            fi
            local sub_mnt
            for sub_mnt in "$mnt" "$mnt/home"; do
                findmnt -rno SOURCE "$sub_mnt" >/dev/null || {
                    check::fail "expected mount missing: $sub_mnt"
                    return 1
                }
            done
            return 0
            ;;
        *)
            error_msg "validation 05: unknown mode '$mode'"
            return 2
            ;;
    esac
}

return 0
