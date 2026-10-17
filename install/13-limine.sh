#!/bin/bash

debug_msg "Starting Limine bootloader stage"

status_msg "Setting up Limine..."

if [[ -z "$LUKS_UUID" && -n "$TARGET_ROOT" ]]; then
	LUKS_UUID=$(cryptsetup luksUUID "$TARGET_ROOT")
fi
[[ -n "$LUKS_UUID" ]] || { error_msg "LUKS_UUID not set; cannot configure Limine kernel cmdline"; exit 1; }
debug_msg "LUKS UUID: $LUKS_UUID"

# Calculate resume_offset for swap file (Hibernation support)
status_msg "Calculating resume_offset for swap file..."
[[ -f "$TARGET_MNT/swap/swapfile" ]] || {
	error_msg "Swapfile is missing; cannot configure hibernation"
	exit 1
}
RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r "$TARGET_MNT/swap/swapfile" 2>/dev/null) || {
	error_msg "Could not calculate the Btrfs swapfile resume offset"
	exit 1
}
[[ "$RESUME_OFFSET" =~ ^[1-9][0-9]*$ ]] || {
	error_msg "Invalid Btrfs swapfile resume offset: $RESUME_OFFSET"
	exit 1
}
debug_msg "Resume offset: $RESUME_OFFSET"

DEFAULT_LIMINE_CONF="$TARGET_MNT/etc/default/limine"
mkdir -p "$(dirname "$DEFAULT_LIMINE_CONF")"

debug_msg "Creating limine configuration with resume_offset=$RESUME_OFFSET"
cat >"$DEFAULT_LIMINE_CONF" <<EOF
TARGET_OS_NAME="Fr0stByte"
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=@ rootfstype=btrfs rd.luks.name=${LUKS_UUID}=${LUKS_NAME} root=/dev/mapper/${LUKS_NAME} resume=/dev/mapper/${LUKS_NAME} resume_offset=${RESUME_OFFSET} zswap.enabled=0"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
EOF

success_msg "Configured /etc/default/limine with hibernation support (resume_offset=${RESUME_OFFSET})"

status_msg "Installing limine-mkinitcpio-hook"
chroot_exec pacman -S --needed --noconfirm limine-mkinitcpio-hook
status_msg "Installed limine-mkinitcpio-hook"

status_msg "Installing Limine..."
chroot_exec limine-install
grep -q "resume_offset=${RESUME_OFFSET}" "$DEFAULT_LIMINE_CONF" || {
	error_msg "Limine configuration does not contain the verified resume offset"
	exit 1
}

# Veryify Limine installation finished succesfully
EFI_PAYLOAD_COUNT=$(find "$TARGET_MNT/boot/EFI" -type f \( -iname '*.efi' -o -iname 'limine*' \) -printf '.' 2>/dev/null | wc -c)
(( EFI_PAYLOAD_COUNT > 0 )) || {
	error_msg "Limine installation did not produce an EFI payload under $TARGET_MNT/boot/EFI"
	exit 1
}
success_msg "Limine installed successfully"
