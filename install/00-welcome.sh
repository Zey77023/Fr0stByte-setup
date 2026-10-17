#!/bin/bash

debug_msg "Starting prerequisites check stage"

# UEFI required
require_paths /sys/firmware/efi/efivars
debug_msg "UEFI mode confirmed"

# Root required
require_root

# efivars should be writable
if [[ ! -w /sys/firmware/efi/efivars ]]; then
    status_msg "Efivars not writable; attempting remount..."
    if mount -o remount,rw /sys/firmware/efi/efivars 2>/dev/null; then
        debug_msg "Successfully remounted efivars as read-write"
    else
        warn_msg "Remount failed; bootloader install may fail"
    fi
else
    debug_msg "Efivars already writable"
fi

# RAM check
RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
RAM_GB=$((RAM_KB / 1048576))
debug_msg "Detected RAM: ${RAM_KB}KB (${RAM_GB}GB)"

if ((RAM_GB < 1)); then
    error_msg "Less than 1GB RAM; installation may fail"

    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1

    warn_msg "Proceeding with less than 1GB RAM"
elif ((RAM_GB < 2)); then
    status_msg "Less than 2GB RAM; installation may be slow"
fi

status_msg "Starting installation..."
