#!/bin/bash

debug_msg "Starting disk partitioning stage"

# LUKS container name
LUKS_NAME="cryptroot"
debug_msg "LUKS container name set to: $LUKS_NAME"

# Classify partition by type UUID
get_part_type() { lsblk -no PARTTYPE "$1" | tr '[:upper:]' '[:lower:]'; }

# Make sure chosen disk is valid for installation
validate_target_disk() {
    local disk="$1" device swap
    local -a devices=()

    [[ -b "$disk" ]] || { error_msg "Target is not a block device: $disk"; exit 1; }
    [[ "$(lsblk -dn -o TYPE "$disk")" == "disk" ]] || {
        error_msg "Target must be a whole disk, not a partition: $disk"
        exit 1
    }

    if lsblk -nrpo MOUNTPOINTS "$disk" | awk 'NF { found=1 } END { exit found ? 0 : 1 }'; then
        error_msg "Target disk has mounted filesystems: $disk"
        exit 1
    fi

    mapfile -t devices < <(lsblk -nrpo NAME "$disk")
    while read -r swap; do
        [[ -n "$swap" ]] || continue
        for device in "${devices[@]}"; do
            if [[ "$swap" == "$device" ]]; then
                error_msg "Target disk has active swap: $swap"
                exit 1
            fi
        done
    done < <(swapon --noheadings --raw --output NAME 2>/dev/null || true)
}

# Check if a partition is mounted
partition_is_mounted() {
    local partition="$1"
    lsblk -nrpo MOUNTPOINTS "$partition" | awk 'NF { found=1 } END { exit found ? 0 : 1 }'
}

debug_msg "Partition type UUIDs - EFI: $EFI_UUID, Linux FS: $LINUX_FS_UUID"

status_msg "Scanning for storage devices..."

# Detect installer media to exclude from disk list
INSTALLER_MEDIA=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null)" 2>/dev/null | head -n1)
if [[ -z "$INSTALLER_MEDIA" ]]; then
    INSTALLER_MEDIA=$(basename "$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null)" 2>/dev/null)
fi
debug_msg "Detected installer media to exclude: $INSTALLER_MEDIA"

# Build disk list: path, size, model, transport
mapfile -t DISKS < <(
    lsblk -d -n -p -o NAME,SIZE,MODEL,TRAN 2>/dev/null |
    grep -Ev '/loop|/rom' |
    grep -vE "^/dev/${INSTALLER_MEDIA}([[:space:]]|$)" |
    awk '{
        model=$3; tran=$4
        if (NF<4) { model=""; tran=$3 }
        if (NF<3) { model=""; tran="" }
        m=(model!="") ? " [" model "]" : ""
        t=(tran!="") ? " (" tran ")" : ""
        print $1 " " $2 m t
    }'
)

if [ ${#DISKS[@]} -eq 0 ]; then
    error_msg "ERROR: No storage devices detected"
    exit 1
fi

# TODO: Check if this printing logic acttually works
status_msg "Detected disks:"
printf '%s\n' "${DISKS[@]}" | while read -r d; do echo "  $d"; done

# Prompt user to select a disk
DISK_CHOICE=$(gum choose --header="Select a target disk for installation:" "${DISKS[@]}" "Cancel Installation")

if [[ "$DISK_CHOICE" == "Cancel Installation" || -z "$DISK_CHOICE" ]]; then
    error_msg "Installation cancelled by user"
    exit 1
fi

SELECTED_DISK=$(echo "$DISK_CHOICE" | awk '{print $1}')
validate_target_disk "$SELECTED_DISK"
status_msg "Selected target: $SELECTED_DISK"

# Prompt user for partitioning method
PART_METHOD=$(gum choose --header="How would you like to partition $SELECTED_DISK?" \
    "Manual Partitioning (cfdisk)" \
    "Full Wipe and Auto-Partition" \
    "Cancel")
debug_msg "Partitioning method: $PART_METHOD"

case $PART_METHOD in
    "Manual Partitioning (cfdisk)")
        while true; do
            cfdisk "$SELECTED_DISK"

            PART_STATUS=$(gum choose --header="Are you satisfied with the partition layout?" \
                "Yes, move to next step" \
                "No, relaunch cfdisk" \
                "Cancel installation")

            case "$PART_STATUS" in
                "Yes, move to next step") break ;;
                "No, relaunch cfdisk") status_msg "Relaunching cfdisk..."; sleep 1 ;;
                "Cancel installation" | "") error_msg "Installation cancelled by user"; exit 1 ;;
            esac
        done
        ;;

    "Full Wipe and Auto-Partition")
        status_msg "Proceeding with Full Wipe and Auto-Partition..."
        INSTALL_MODE="AUTO"
        TARGET_DISK="$SELECTED_DISK"
        TARGET_BOOT="NONE"
        TARGET_ROOT="NONE"
        debug_msg "Auto-partition mode set - Disk: $TARGET_DISK"
        return 0
        ;;

    "Cancel" | "")
        error_msg "Installation cancelled by user"
        exit 1
        ;;
esac

# Manual: select boot and root partitions
if [[ "$PART_METHOD" == "Manual Partitioning (cfdisk)" ]]; then
    status_msg "Scanning partitions on $SELECTED_DISK..."

    mapfile -t PARTITIONS < <(
        lsblk -r -n -p --output-separator $'\t' -o NAME,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINTS "$SELECTED_DISK" |
        awk -F '\t' '$2=="part" && $6=="" {
            fs=$3; label=$4; size=$5
            extra=""
            if (fs!="") extra=extra " [" fs "]"
            if (label!="") extra=extra " \"" label "\""
            print $1 "\t" extra " (" size ")"
        }'
    )

    if [ ${#PARTITIONS[@]} -eq 0 ]; then
        error_msg "ERROR: No partitions found on $SELECTED_DISK. Did you forget to write the changes in cfdisk?"
        exit 1
    fi

    # Boot partition
    BOOT_PART=$(gum choose --header="Where should the BOOTLOADER (EFI/Boot) be installed?" "${PARTITIONS[@]}")
    [[ -z "$BOOT_PART" ]] && { error_msg "Action cancelled"; exit 1; }
    TARGET_BOOT=$(partition_choice_device "$BOOT_PART")
    [[ "$(get_part_type "$TARGET_BOOT")" != "$EFI_UUID" ]] && \
        { error_msg "ERROR: $TARGET_BOOT is not an EFI System partition type!"; exit 1; }
    partition_is_mounted "$TARGET_BOOT" && \
        { error_msg "ERROR: $TARGET_BOOT is mounted; unmount it before continuing"; exit 1; }
    status_msg "Bootloader partition set to: $TARGET_BOOT"

    # Root partition
    REMAINING=()
    for p in "${PARTITIONS[@]}"; do
        [[ "$(partition_choice_device "$p")" != "$TARGET_BOOT" ]] || continue
        REMAINING+=("$p")
    done

    if [ ${#REMAINING[@]} -eq 0 ]; then
        error_msg "ERROR: No partitions left for Root!"
        exit 1
    fi

    PARTITIONS=("${REMAINING[@]}")

    ROOT_PART=$(gum choose --header="Where should the ROOT system (/) be installed?" "${PARTITIONS[@]}")
    [[ -z "$ROOT_PART" ]] && { error_msg "Action cancelled"; exit 1; }
    TARGET_ROOT=$(partition_choice_device "$ROOT_PART")
    [[ "$(get_part_type "$TARGET_ROOT")" != "$LINUX_FS_UUID" ]] && \
        { error_msg "ERROR: $TARGET_ROOT is not a Linux Filesystem type!"; exit 1; }
    partition_is_mounted "$TARGET_ROOT" && \
        { error_msg "ERROR: $TARGET_ROOT is mounted; unmount it before continuing"; exit 1; }
    status_msg "Root partition set to: $TARGET_ROOT"

    gum confirm "Use these partitions? Boot: $TARGET_BOOT | Root: $TARGET_ROOT" --default=no || {
        error_msg "Partition selection was not confirmed"
        exit 1
    }

    success_msg "Partitioning complete
Boot: $TARGET_BOOT
Root: $TARGET_ROOT"

    INSTALL_MODE="MANUAL"
    TARGET_DISK="$SELECTED_DISK"
    debug_msg "Manual partition mode set - Disk: $TARGET_DISK, Boot: $TARGET_BOOT, Root: $TARGET_ROOT"
fi
