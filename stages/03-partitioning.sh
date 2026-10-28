#!/bin/bash

# stage 03 — partitioning: target-disk selection + partition-mode choice.

STAGE_ID="03-partitioning"
STAGE_KIND="destructive"
STAGE_DESC="Select target disk and partitioning mode; cfdisk loop; boot/root picking"
STAGE_APIS=(core.state system.disk)

run_stage() {
    status_msg "Scanning for storage devices..."

    local -a st_disks=()
    disk::enumerate st_disks || return 1

    status_msg "Detected disks:"
    printf '%s\n' "${st_disks[@]}" | sed 's/^/  /'

    dp_cancel_full() {
        error_msg "Installation cancelled by user"
        return 1
    }

    local st_choice st_disk
    st_choice=$(ui::choose "Select a target disk for installation:" \
        "${st_disks[@]}" "Cancel Installation")
    if [[ "$st_choice" == "Cancel Installation" || -z "$st_choice" ]]; then
        dp_cancel_full
        return 1
    fi
    st_disk="$(printf '%s' "$st_choice" | awk '{print $1}')"
    status_msg "Selected target: $st_disk"

    local st_method
    st_method=$(ui::choose "How would you like to partition $st_disk?" \
        "Manual Partitioning (cfdisk)" \
        "Full Wipe and Auto-Partition" \
        "Cancel")
    debug_msg "Partitioning method: $st_method"

    if [[ "$st_method" == "Full Wipe and Auto-Partition" ]]; then
        state_set "partition/mode" "AUTO"
        state_set "partition/disk" "$st_disk"
        debug_msg "Auto-partition mode set - Disk: $st_disk"
        return 0
    fi

    if [[ "$st_method" != "Manual Partitioning (cfdisk)" ]]; then
        dp_cancel_full
        return 1
    fi

    dp_ask_satisfied() {
        ui::choose "Are you satisfied with the partition layout?" \
            "Yes, move to next step" \
            "No, relaunch cfdisk" \
            "Cancel installation"
    }

    dp_relaunch() {
        while :; do
            if ! exec_cmd cfdisk "$st_disk"; then
                return 1
            fi
            local answer
            if ! answer=$(dp_ask_satisfied); then
                return 1
            fi
            case "$answer" in
                "Yes, move to next step") return 0 ;;
                "No, relaunch cfdisk") status_msg "Relaunching cfdisk..."; sleep 1 ;;
                "Cancel installation" | "") dp_cancel_full; return 1 ;;
            esac
        done
    }
    if ! dp_relaunch; then
        return 1
    fi

    status_msg "Scanning partitions on $st_disk..."

    dp_list_partitions() {
        local disk="$1"
        mapfile -t st_parts < <(
            lsblk -r -n -p -o NAME,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINTS "$disk" |
            awk -F ' ' '$2=="part" && $6=="" {
                fs=$3; label=$4; size=$5
                extra=""
                if (fs!="") extra=extra " [" fs "]"
                if (label!="") extra=extra " \"" label "\""
                print $1 "\t" extra " (" size ")"
            }'
        )
        (( ${#st_parts[@]} > 0 )) || {
            error_msg "No partitions found on $disk. Did you forget to write the changes in cfdisk?"
            return 1
        }
        return 0
    }
    local -a st_parts=()
    if ! dp_list_partitions "$st_disk"; then
        return 1
    fi

    local st_boot_row st_root_row st_boot st_root
    st_boot_row=$(ui::choose "Where should the BOOTLOADER (EFI/Boot) be installed?" "${st_parts[@]}") || return 1
    [[ -n "$st_boot_row" ]] || { error_msg "Action cancelled"; return 1; }
    st_boot=$(disk::row_device "$st_boot_row")
    if [[ "$(disk::part_type "$st_boot")" != "$_DISK_EFI_PARTTYPE" ]]; then
        error_msg "$st_boot is not an EFI System partition type!"
        return 1
    fi
    if disk::is_mounted "$st_boot"; then
        error_msg "$st_boot is mounted; unmount it before continuing"
        return 1
    fi
    status_msg "Bootloader partition set to: $st_boot"

    local -a st_remaining=()
    local row
    for row in "${st_parts[@]}"; do
        [[ "$(disk::row_device "$row")" != "$st_boot" ]] || continue
        st_remaining+=("$row")
    done
    (( ${#st_remaining[@]} > 0 )) || {
        error_msg "No partitions left for Root!"
        return 1
    }

    st_root_row=$(ui::choose "Where should the ROOT system (/) be installed?" "${st_remaining[@]}") || return 1
    [[ -n "$st_root_row" ]] || { error_msg "Action cancelled"; return 1; }
    st_root=$(disk::row_device "$st_root_row")
    if [[ "$(disk::part_type "$st_root")" != "$_DISK_LINUXFS_PARTTYPE" ]]; then
        error_msg "$st_root is not a Linux Filesystem type!"
        return 1
    fi
    if disk::is_mounted "$st_root"; then
        error_msg "$st_root is mounted; unmount it before continuing"
        return 1
    fi
    status_msg "Root partition set to: $st_root"

    if ! ui::confirm "partition_confirm" \
        "Use these partitions? Boot: $st_boot | Root: $st_root" "no"; then
        error_msg "Partition selection was not confirmed"
        return 1
    fi

    state_set "partition/mode" "MANUAL"
    state_set "partition/disk" "$st_disk"
    state_set "partition/boot" "$st_boot"
    state_set "partition/root" "$st_root"

    success_msg "Partitioning complete
    Boot: $st_boot
    Root: $st_root"
    return 0
}
