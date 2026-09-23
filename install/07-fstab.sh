#!/bin/bash

debug_msg "Starting fstab generation stage"

require_paths "$TARGET_MNT"

# Generate fstab and verify it
mkdir -p "$TARGET_MNT/etc"
genfstab -U "$TARGET_MNT" >"$TARGET_MNT/etc/fstab"
chroot_exec findmnt --verify --tab-file /etc/fstab
success_msg "fstab written to $TARGET_MNT/etc/fstab"
