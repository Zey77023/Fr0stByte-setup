#!/bin/bash

# stage 00 — welcome: Checks if efivars are present and writable.
# Installer is based on UEFI being available, so it will fail when it
# is not able to detect efivars.

STAGE_ID="00-welcome"
STAGE_KIND="informational"
STAGE_DESC="Prereqs asserted by validation; efi vars remount + install banner"
STAGE_APIS=()

run_stage() {
    if [[ -d /sys/firmware/efi/efivars && ! -w /sys/firmware/efi/efivars ]]; then
        status_msg "Efivars not writable; attempting remount..."
        if exec_cmd mount -o remount,rw /sys/firmware/efi/efivars; then
            debug_msg "Successfully remounted efivars as read-write"
        else
            warn_msg "Remount failed; bootloader install may fail"
        fi
    else
        debug_msg "Efivarfs writable (or absent); no remount needed"
    fi

    status_msg "Starting installation..."
    return 0
}
