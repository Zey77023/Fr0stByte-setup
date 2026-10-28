#!/bin/bash

# stage 16 — snapper: installation, configuration, testing and
# enablement of cleanup timers. Optional installation of snap-pac
# for snapshots during pacman operations.

STAGE_ID="16-snapper"
STAGE_KIND="mutating"
STAGE_DESC="Configure Snapper btrfs snapshots (retention, roundtrip test, timers)"
STAGE_APIS=(
    core.state core.ui
    config.snapper pkg.pacman system.chroot
)

run_stage() {
    debug_msg "Starting Snapper configuration stage"
    status_msg "Configuring Snapper for Btrfs snapshots..."

    debug_msg "Installing and configuring snapper"
    snapper::setup "$TARGET_MNT" || return 1
    success_msg "Snapper installed and configured against @snapshots"

    snapper::roundtrip_validate "$TARGET_MNT" || return 1

    if ! snapper::timers "$TARGET_MNT"; then
        warn_msg "snapper timeline/cleanup timers could not be enabled"
    fi

    if ui::confirm snap_pac \
        "Enable automatic Snapper snapshots for pacman transactions?" "no"; then
        local st_probe_rc=1
        chroot_exec "$TARGET_MNT" --expect "0 1" --code st_probe_rc \
            -- pacman -Si snap-pac || true
        if (( st_probe_rc != 0 )); then
            warn_msg "snap-pac is unavailable in the enabled repositories; skipping it"
        else
            chroot_exec "$TARGET_MNT" -- pacman -S --needed --noconfirm snap-pac || return 1
            success_msg "snap-pac installed for pacman transaction snapshots"
        fi
    else
        status_msg "snap-pac disabled; pacman transactions will not create automatic snapshots"
    fi

    state_set "snapper/configured" "done"
    success_msg "Snapshot cleanup and timeline services configured"
    return 0
}
