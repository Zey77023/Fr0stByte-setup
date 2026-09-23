#!/bin/bash

debug_msg "Starting review stage"

status_msg "Review your installation settings before proceeding..."

# Load installer state
REVIEW_DISK="$TARGET_DISK"
REVIEW_MODE="$INSTALL_MODE"
debug_msg "Review - Disk: $REVIEW_DISK, Mode: $REVIEW_MODE"

PARTITION_TEXT=$([[ "$REVIEW_MODE" == "AUTO" ]] && echo "Automatic (disk will be wiped)" || echo "Manual (existing partitions)")

# Warn before making changes to disk
warn_msg "FINAL REVIEW - DATA WILL BE ERASED"
status_msg "───────────────────────────────────────"

status_msg "Target Disk    : ${REVIEW_DISK}"
status_msg "Partitioning   : ${PARTITION_TEXT}"
status_msg "Encryption     : LUKS2 on root partition"
status_msg "Filesystem     : Btrfs with subvolumes"
status_msg "Bootloader     : LIMINE"

status_msg "───────────────────────────────────────"

status_msg "Btrfs Subvolumes:"
status_msg "@          → / (root)"
status_msg "@home      → /home"
status_msg "@var_log   → /var/log"
status_msg "@var_cache → /var/cache"
status_msg "@snapshots → /.snapshots"
status_msg "@swap      → /swap (hibernation)"

status_msg "───────────────────────────────────────"
warn_msg "WARNING: All data on ${REVIEW_DISK} will be lost!"

# User confirmation before writing to disk
if ! gum confirm "Proceed with disk formatting and encryption?" --default=no; then
    error_msg "Installation cancelled by user"
    exit 1
fi

status_msg "Proceeding with disk setup..."
