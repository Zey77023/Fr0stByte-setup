#!/bin/bash

# stage 13 — Limine bootloader: LUKS cmdline (/etc/default/limine) with hibernation and encryption support.

STAGE_ID="13-limine"
STAGE_KIND="mutating"
STAGE_DESC="Install Limine with LUKS cmdline, hibernation offsets and hidden-menu directives"
STAGE_APIS=(core.state config.limine system.btrfs system.chroot)

run_stage() {
    debug_msg "Starting Limine bootloader stage"
    status_msg "Setting up Limine..."

    local st_uuid st_luks_name st_swappath st_swapfile st_offset

    st_uuid="$(state_get luks/uuid "")"
    debug_msg "LUKS UUID: $st_uuid"

    st_luks_name="$(state_get luks/name "cryptroot")"
    st_swappath="$(state_get swap/file "")"
    st_swapfile="${TARGET_MNT}${st_swappath}"

    status_msg "Calculating resume_offset for swap file..."
    if [[ ${FR0ST_DRYRUN:-0} != "1" && ! -f "$st_swapfile" ]]; then
        error_msg "Swapfile is missing; cannot configure hibernation"
        return 1
    fi
    btrfs::resume_offset st_offset "$st_swapfile" || return 1
    debug_msg "Resume offset: $st_offset"

    limine::configure "$TARGET_MNT" "$st_uuid" "$st_luks_name" "$st_offset" \
        || return 1

    limine::install_hook "$TARGET_MNT" || return 1
    limine::install "$TARGET_MNT" || return 1

    if [[ ${FR0ST_DRYRUN:-0} != "1" ]] \
        && ! grep -q "resume_offset=${st_offset}" "$TARGET_MNT/etc/default/limine"; then
        error_msg "Limine configuration does not contain the verified resume offset"
        return 1
    fi

    limine::hidden_menu "$TARGET_MNT" || return 1
    limine::assert_assets "$TARGET_MNT" || return 1

    state_set "limine/configured" "done"
    success_msg "Limine installed with hidden menu (timeout: 1, quiet: yes)"
    return 0
}
