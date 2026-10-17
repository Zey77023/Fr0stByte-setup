#!/bin/bash

debug_msg "Starting pacman configuration stage"

status_msg "Configuring pacman with official repositories..."

PACMAN_CONF="$TARGET_MNT/etc/pacman.conf"
require_paths "$PACMAN_CONF"

# Enable multilib
sed -i '/^\[multilib\]/,/Include/s/^#//' "$PACMAN_CONF"

# Enable Chaotic-AUR on user confirmation
if gum confirm "Enable the third-party Chaotic-AUR repository?" --default=no; then
	CHAOTIC_KEY="3056513887B78AEB"
	status_msg "Importing Chaotic-AUR signing key..."
	chroot_exec pacman-key --recv-key "$CHAOTIC_KEY" --keyserver keyserver.ubuntu.com
	chroot_exec pacman-key --lsign-key "$CHAOTIC_KEY"
	chroot_exec pacman -U --noconfirm \
		'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
		'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

	if ! grep -q '^\[chaotic-aur\]' "$PACMAN_CONF"; then
		cat >>"$PACMAN_CONF" <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
	fi
	chroot_exec pacman -Syu --noconfirm
	success_msg "Chaotic-AUR enabled and package databases refreshed"
else
	sed -i '/^\[chaotic-aur\]/,/^$/d' "$PACMAN_CONF"
	status_msg "Chaotic-AUR remains disabled"
fi

# Eye candy
grep -q '^ILoveCandy$' "$PACMAN_CONF" || sed -i '/^\[options\]/a ILoveCandy' "$PACMAN_CONF"
grep -q '^VerbosePkgLists$' "$PACMAN_CONF" || sed -i '/^\[options\]/a VerbosePkgLists' "$PACMAN_CONF"
success_msg "Enabled ILoveCandy and VerbosePkgLists"

debug_msg "Refreshing official pacman databases"
chroot_exec pacman -Syu --noconfirm

success_msg "Pacman repositories configured and databases refreshed"
