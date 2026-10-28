#!/bin/bash

# stage 04 — review: final settings recap and user confirmation.

STAGE_ID="04-review"
STAGE_KIND="interactive"
STAGE_DESC="Final review of target disk/partitioning; destructive gate"
STAGE_APIS=(core.state)

run_stage() {
    debug_msg "Starting review stage"

    status_msg "Review your installation settings before proceeding..."

    local st_disk st_mode partition_text
    st_disk="$(state_get partition/disk)"
    st_mode="$(state_get partition/mode)"
    debug_msg "Review - Disk: $st_disk, Mode: $st_mode"

    if [[ "$st_mode" == "AUTO" ]]; then
        partition_text="Automatic (disk will be wiped)"
    else
        partition_text="Manual (existing partitions)"
    fi

    warn_msg "FINAL REVIEW - DATA WILL BE ERASED"
    status_msg "───────────────────────────────────────"

    status_msg "Target Disk    : ${st_disk}"
    status_msg "Partitioning   : ${partition_text}"
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
    warn_msg "WARNING: All data on ${partition_text} will be lost!"

    if ! ui::confirm "partition_confirm" \
        "Proceed with disk formatting and encryption?" "no"; then
        error_msg "Installation cancelled by user"
        return 1
    fi

    status_msg "Proceeding with disk setup..."
    return 0
}
