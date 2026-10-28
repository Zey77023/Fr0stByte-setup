#!/bin/bash

# stage 11 — initcpio: configure and generate initcpio for btrfs, encryption,
# hibernation and optionally NVIDIA

STAGE_ID="11-initcpio"
STAGE_KIND="mutating"
STAGE_DESC="Configure and generate mkinitcpio for btrfs, encryption, hibernation and optionally NVIDIA"
STAGE_APIS=(core.state config.initramfs system.detect pkg.pacman system.chroot)

run_stage() {
    debug_msg "Starting initcpio configuration stage"
    status_msg "Configuring mkinitcpio for Btrfs..."

    local st_img
    detect::microcode_img st_img || return 1
    if [[ -n "$st_img" ]] && [[ ${FR0ST_DRYRUN:-0} != "1" ]]; then
        status_msg "Microcode image: $st_img"
    fi
    debug_msg "Microcode binary: $st_img"

    local -a st_modules=(btrfs)
    local -a st_binaries=("/usr/bin/btrfs")
    local -a st_hooks=(sd-encrypt resume)
    initramfs::configure "$TARGET_MNT" st_modules st_binaries st_hooks ||
        return 1

    if [[ ${FR0ST_DRYRUN:-0} != "1" ]] &&
        pkg::is_installed "$TARGET_MNT" "nvidia-open-dkms"; then
        detect::nvidia_modules_present "$TARGET_MNT" || {
            error_msg "nvidia-open-dkms is installed but produced no kernel modules"
            return 1
        }
        local -a st_nvidia_modules=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
        initramfs::configure "$TARGET_MNT" st_nvidia_modules st_binaries st_hooks ||
            return 1
        status_msg "Added NVIDIA modules for early KMS"
    fi

    initramfs::rebuild "$TARGET_MNT" || return 1

    state_set "initramfs/done" "done"
    success_msg "mkinitcpio configured for Btrfs and initramfs rebuilt"
    return 0
}
