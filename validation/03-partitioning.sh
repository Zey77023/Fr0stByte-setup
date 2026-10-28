#!/bin/bash

# validation/03-partitioning — disk-level safety assertions.
#   pre : no assertion (disk choice happens interactively inside the stage).
#   post: whole-disk / unmounted / no-active-swap for the chosen disk; for
#         MANUAL also the boot/root partition types and unmounted state.

VALIDATE_APIS=(validation.core.check core.state system.disk)

validate::03_partitioning() {
    local mode="$1" mnt="${2:-}"
    local disk p_mode

    case "$mode" in
        pre)
            return 0
            ;;
        post)
            if ! check::require_state "partition/disk" "03-partitioning"; then
                return 1
            fi
            if ! check::require_state "partition/mode" "03-partitioning"; then
                return 1
            fi
            disk="$(state_get partition/disk)"
            p_mode="$(state_get partition/mode)"

            if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
                # only the MANUAL state-trio consistency below holds under dry-run
                if [[ "$p_mode" == "MANUAL" ]]; then
                    check::assert_state_keys "partition/boot" "partition/root" \
                        "03-partitioning" || return 1
                fi
                return 0
            fi

            check::assert_whole_disk "$disk" || return 1
            check::assert_no_mounts "$disk" || return 1
            check::assert_no_swap_on "$disk" || return 1

            if [[ "$p_mode" == "MANUAL" ]]; then
                check::assert_state_keys "partition/boot" "partition/root" \
                    "03-partitioning" || return 1
                local st_boot st_root
                st_boot="$(state_get partition/boot)"
                st_root="$(state_get partition/root)"
                check::assert_parttype "$st_boot" "$_DISK_EFI_PARTTYPE" || return 1
                check::assert_parttype "$st_root" "$_DISK_LINUXFS_PARTTYPE" || return 1
                if disk::is_mounted "$st_boot"; then
                    check::fail "$st_boot is mounted; unmount it before continuing"
                    return 1
                fi
                if disk::is_mounted "$st_root"; then
                    check::fail "$st_root is mounted; unmount it before continuing"
                    return 1
                fi
            fi
            return 0
            ;;
        *)
            error_msg "validation 03: unknown mode '$mode'"
            return 2
            ;;
    esac
}

return 0
