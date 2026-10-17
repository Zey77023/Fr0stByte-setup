#!/bin/bash

debug_msg "Starting finalization stage"

# Final top level verification
status_msg "Verifying installed storage and boot configuration..."
chroot_exec findmnt --verify --tab-file /etc/fstab
[[ -n "$LUKS_UUID" && -n "$TARGET_ROOT" ]] || {
    error_msg "Encryption identifiers are missing from the final verification"
    exit 1
}
cryptsetup luksDump "$TARGET_ROOT" >/dev/null
[[ "$(fstab_entry_count "$TARGET_MNT/etc/fstab" "/swap/swapfile" "none" "swap")" -eq 1 ]] || {
    error_msg "Final fstab verification found an invalid swapfile entry"
    exit 1
}
[[ -s "$TARGET_MNT/etc/default/limine" ]] || {
    error_msg "Limine configuration is missing from the installed system"
    exit 1
}
grep -Eq 'resume=/dev/mapper/[^ ]+ resume_offset=[1-9][0-9]*' "$TARGET_MNT/etc/default/limine" || {
    error_msg "Limine configuration has no valid hibernation resume parameters"
    exit 1
}
find "$TARGET_MNT/boot" -maxdepth 1 -type f -name 'initramfs-*.img' -print -quit | grep -q . || {
    error_msg "No initramfs image found in the target boot directory"
    exit 1
}
SNAPSHOT_SOURCE=$(findmnt -n -o SOURCE -T "$TARGET_MNT/.snapshots" 2>/dev/null || true)
[[ "$SNAPSHOT_SOURCE" == *"@snapshots"* ]] || {
    error_msg "Final /.snapshots mount is not backed by @snapshots"
    exit 1
}

FINAL_HOSTNAME=$(cat "$TARGET_MNT/etc/hostname" 2>/dev/null || echo "unknown")
FINAL_USER=$(chroot_exec ls /home 2>/dev/null | head -n1 || echo "none")
FINAL_DISK=$(lsblk -no PKNAME "$TARGET_ROOT" 2>/dev/null | head -n1)
FINAL_DISK=${FINAL_DISK:-$TARGET_DISK}
FINAL_TZ=$(cat "$TARGET_MNT/etc/timezone" 2>/dev/null || readlink "$TARGET_MNT/etc/localtime" 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "unknown")
FINAL_LOCALE=$(grep "^LANG=" "$TARGET_MNT/etc/locale.conf" 2>/dev/null | cut -d= -f2 || echo "unknown")

status_msg "Installation Summary"
status_msg "─────────────────────────────────"

status_msg "Hostname      : $FINAL_HOSTNAME"
status_msg "User          : $FINAL_USER"
status_msg "Timezone      : $FINAL_TZ"
status_msg "Locale        : $FINAL_LOCALE"
status_msg "Disk          : /dev/$FINAL_DISK"
status_msg "Encryption    : LUKS2 on root"
status_msg "Filesystem    : Btrfs with subvolumes"
status_msg "Bootloader    : Limine"
PERFORMANCE_PROFILE=$(sed -n 's/^PROFILE_\([^=]*\)="enabled"/\1/p' "$TARGET_MNT/etc/fr0stbyte/performance.conf" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
PERFORMANCE_PROFILE=${PERFORMANCE_PROFILE:-default}
status_msg "Performance   : $PERFORMANCE_PROFILE"

status_msg "─────────────────────────────────"
status_msg "Log file saved to: ${LOG_FILE}"

mkdir -p "$TARGET_MNT/var/log"
cp "$LOG_FILE" "$TARGET_MNT/var/log/fr0stbyte-install.log" 2>/dev/null || true
success_msg "Install log copied to /var/log/fr0stbyte-install.log in target system"

# Installation done, what to do next?
NEXT_ACTION=$(gum choose --header="Installation complete. What would you like to do?" \
    "Reboot now" \
    "Chroot into system" \
    "Exit to shell")

case "$NEXT_ACTION" in
    "Reboot now")
        status_msg "Unmounting filesystems..."
        cleanup_target
        success_msg "Unmounted. Rebooting..."
        reboot
        ;;
    "Chroot into system")
        status_msg "Dropping into chroot. Type 'exit' when done"
        arch-chroot "$TARGET_MNT"
        status_msg "Exited chroot"
        ;;
    "Exit to shell")
        status_msg "Exiting installer. Filesystems remain mounted at $TARGET_MNT"
        return 0
        ;;
esac
