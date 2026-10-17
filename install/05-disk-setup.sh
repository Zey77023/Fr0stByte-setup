#!/bin/bash

debug_msg "Starting disk formatting and mounting stage"

# Mount options for Btrfs subvolumes
MOUNT_OPTS="compress=zstd:1,noatime"

debug_msg "Mount options: $MOUNT_OPTS"
debug_msg "Mapper device: $MAPPER_DEV"

# Shreds and removes a temporary password file securely
cleanup_pass_file() {
    local pass_file="$1"
    shred -u "$pass_file" 2>/dev/null || rm -f "$pass_file"
}

status_msg "Starting Disk Formatting and Mounting..."

# AUTO mode: partition the disk
if [ "$INSTALL_MODE" == "AUTO" ]; then
    debug_msg "Auto-partition mode - Target disk: $TARGET_DISK"

    gum spin --title "Clearing partition table on $TARGET_DISK..." -- \
        sgdisk -Z "$TARGET_DISK"
    debug_msg "Created new partition table on $TARGET_DISK"

    gum spin --title "Creating EFI partition..." -- \
        sgdisk -n 1:0:+2G -t 1:ef00 -c 1:$BOOT_LABEL "$TARGET_DISK"
    debug_msg "Created EFI partition on $TARGET_DISK"

    gum spin --title "Creating root partition..." -- \
        sgdisk -n 2:0:0 -t 2:8300 -c 2:$ROOT_LABEL "$TARGET_DISK"
    debug_msg "Created root partition on $TARGET_DISK"

    gum spin --title "Refreshing partition table..." -- partprobe "$TARGET_DISK"
    udevadm settle
    debug_msg "Partition table refreshed on $TARGET_DISK"

    # Verify no problems with the partition table
    sgdisk -v "$TARGET_DISK"

    mapfile -t BOOT_PARTITIONS < <(lsblk -lp -o NAME,PARTLABEL "$TARGET_DISK" | awk -v label="$BOOT_LABEL" '$2 == label {print $1}')
    mapfile -t ROOT_PARTITIONS < <(lsblk -lp -o NAME,PARTLABEL "$TARGET_DISK" | awk -v label="$ROOT_LABEL" '$2 == label {print $1}')

    [[ ${#BOOT_PARTITIONS[@]} -eq 1 && ${#ROOT_PARTITIONS[@]} -eq 1 ]] || {
        error_msg "Expected exactly one EFI and one ROOT partition after partitioning."
        exit 1
    }
    TARGET_BOOT="${BOOT_PARTITIONS[0]}"
    TARGET_ROOT="${ROOT_PARTITIONS[0]}"

    debug_msg "Detected partitions - Boot: $TARGET_BOOT, Root: $TARGET_ROOT"
    [[ -z "$TARGET_BOOT" || -z "$TARGET_ROOT" ]] && \
        { error_msg "Could not find partitions on $TARGET_DISK after creation."; exit 1; }
    [[ "$(lsblk -no PARTTYPE "$TARGET_BOOT" | tr '[:upper:]' '[:lower:]')" == $EFI_UUID ]] || {
        error_msg "Created boot partition has an unexpected partition type"
        exit 1
    }
    [[ "$(lsblk -no PARTTYPE "$TARGET_ROOT" | tr '[:upper:]' '[:lower:]')" == $LINUX_FS_UUID ]] || {
        error_msg "Created root partition has an unexpected partition type"
        exit 1
    }
    [[ "$(blockdev --getsize64 "$TARGET_BOOT")" -ge $((2 * 1024 * 1024 * 1024)) ]] || {
        error_msg "EFI partition is smaller than 2 GiB"
        exit 1
    }
    [[ "$(blockdev --getsize64 "$TARGET_ROOT")" -gt $((1024 * 1024 * 1024)) ]] || {
        error_msg "Root partition is too small"
        exit 1
    }
    success_msg "Found: Boot -> $TARGET_BOOT | Root -> $TARGET_ROOT"
fi

# LUKS encryption
status_msg "Setting up LUKS encryption on $TARGET_ROOT"
LUKS_PASS=$(request_password "LUKS") || exit 1

PASS_TMP=$(mktemp)
chmod 600 "$PASS_TMP"
echo -n "$LUKS_PASS" > "$PASS_TMP"

debug_msg "Formatting LUKS2 container on $TARGET_ROOT"
if ! cryptsetup luksFormat --type luks2 --batch-mode --force-password "$TARGET_ROOT" -d "$PASS_TMP"; then
    cleanup_pass_file "$PASS_TMP"
    unset LUKS_PASS PASS_TMP
    error_msg "LUKS formatting failed"
    exit 1
fi
if ! cryptsetup luksDump "$TARGET_ROOT" >/dev/null; then
    cleanup_pass_file "$PASS_TMP"
    unset LUKS_PASS PASS_TMP
    error_msg "LUKS metadata verification failed"
    exit 1
fi
debug_msg "Opening LUKS container as $LUKS_NAME"
if ! cryptsetup open "$TARGET_ROOT" "$LUKS_NAME" -d "$PASS_TMP"; then
    cleanup_pass_file "$PASS_TMP"
    unset LUKS_PASS PASS_TMP
    error_msg "Could not open the newly formatted LUKS container"
    exit 1
fi
register_mapper "$LUKS_NAME"

cleanup_pass_file "$PASS_TMP"
unset LUKS_PASS PASS_TMP
debug_msg "LUKS setup complete"

LUKS_UUID=$(cryptsetup luksUUID "$TARGET_ROOT")
debug_msg "LUKS UUID: $LUKS_UUID"

# LUKS header backup
if gum confirm "Back up the LUKS header now?" --default=no; then
    HEADER_DIR=$(gum input --placeholder "/path/to/external/backup/directory")
    if [[ -z "$HEADER_DIR" || ! -d "$HEADER_DIR" ]]; then
        error_msg "LUKS header backup directory does not exist: ${HEADER_DIR:-<empty>}"
        exit 1
    fi
    HEADER_BACKUP="$HEADER_DIR/${LUKS_UUID}.luks-header"
    cryptsetup luksHeaderBackup "$TARGET_ROOT" --header-backup-file "$HEADER_BACKUP"
    [[ -s "$HEADER_BACKUP" ]] || {
        error_msg "LUKS header backup was not created or is empty"
        exit 1
    }
    chmod 600 "$HEADER_BACKUP"
    success_msg "LUKS header backup written to: $HEADER_BACKUP"
else
    warn_msg "No LUKS header backup was created"
fi

# Formatting
debug_msg "Formatting boot partition: $TARGET_BOOT (FAT32)"
gum spin --title "Formatting Boot ($TARGET_BOOT)..." -- mkfs.fat -F32 "$TARGET_BOOT"
debug_msg "Formatting root partition: $MAPPER_DEV (Btrfs)"
gum spin --title "Formatting Root ($MAPPER_DEV)..." -- mkfs.btrfs -f "$MAPPER_DEV"

# Btrfs subvolumes
status_msg "Creating Btrfs Subvolumes..."

SUBVOLUMES=("@" "@home" "@var_log" "@var_cache" "@snapshots" "@swap")
SUBVOLUMES_MOUNTS=("/" "/home" "/var/log" "/var/cache" "/.snapshots" "/swap")
debug_msg "Subvolumes to create: ${SUBVOLUMES[*]}"

# Create subvolumes
mount "$MAPPER_DEV" /mnt
register_mount /mnt
for sub in "${SUBVOLUMES[@]}"; do
    debug_msg "Creating subvolume: $sub"
    gum spin --spinner dot --title "Creating subvolume: $sub" -- \
        btrfs subvolume create "/mnt/$sub"
done

# nodatacow on @swap for swap file support
debug_msg "Setting nodatacow attribute on @swap subvolume"
chattr +C "/mnt/@swap"
status_msg "Set nodatacow on @swap subvolume"

# Swap file for hibernation
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
SWAP_SIZE_GB=$(( (TOTAL_RAM_KB + 1024 * 1024 - 1) / (1024 * 1024) ))
SWAP_SIZE_MB=$((SWAP_SIZE_GB * 1024))
debug_msg "Total RAM: ${TOTAL_RAM_KB}KB, Swap size: ${SWAP_SIZE_GB}GiB (${SWAP_SIZE_MB}MB)"

status_msg "Creating swap file (${SWAP_SIZE_MB}MB) for hibernation..."
touch "/mnt/@swap/swapfile"
chmod 600 "/mnt/@swap/swapfile"
dd if=/dev/zero of="/mnt/@swap/swapfile" bs=1M count="$SWAP_SIZE_MB" status=progress
mkswap "/mnt/@swap/swapfile"
[[ "$(stat -c '%s' "/mnt/@swap/swapfile")" -ge "$((SWAP_SIZE_MB * 1024 * 1024))" ]] || {
    error_msg "Swapfile is smaller than the requested RAM-sized allocation"
    exit 1
}
swapon "/mnt/@swap/swapfile"
swapon --show=NAME --noheadings | grep -Fq "/mnt/@swap/swapfile" || {
    swapoff "/mnt/@swap/swapfile" 2>/dev/null || true
    error_msg "Swapfile could not be activated for verification"
    exit 1
}
swapoff "/mnt/@swap/swapfile"
success_msg "Swap file created at /swap/swapfile"

SWAP_FILE="/swap/swapfile"
debug_msg "Swap file path: $SWAP_FILE"
umount /mnt

# Mount all filesystems
status_msg "Mounting filesystems..."

for i in "${!SUBVOLUMES[@]}"; do
    SV="${SUBVOLUMES[$i]}"
    MNT_SUFFIX="${SUBVOLUMES_MOUNTS[$i]}"
    TARGET=$(echo "/mnt${MNT_SUFFIX}" | sed 's#//#/#')
    debug_msg "Mounting subvolume $SV to $TARGET"
    gum spin --spinner dot --title "Mounting $SV to $TARGET" -- \
        mount -o "$MOUNT_OPTS,subvol=$SV" --mkdir "$MAPPER_DEV" "$TARGET"
    register_mount "$TARGET"
done

debug_msg "Mounting boot partition: $TARGET_BOOT -> /mnt/boot"
mount --mkdir "$TARGET_BOOT" /mnt/boot
register_mount /mnt/boot

success_msg "Disk setup complete. Hierarchy mounted at /mnt"
