#!/bin/bash
# stage 12 — pacman: multilib + Chaotic-AUR + eye candy in the target's
# pacman.conf, then the full database refresh. D-5: Chaotic-AUR is
# enabled unconditionally (resolves TODO D4 — limine-mkinitcpio-hook is
# only available from chaotic-aur, so there is no confirmation prompt);
# post-mutation content asserts live in validation/12 (§7 key
# aur/chaotic).

STAGE_ID="12-pacman"
STAGE_KIND="mutating"
STAGE_DESC="Enable multilib + Chaotic-AUR + eye candy in pacman.conf and refresh databases"
STAGE_APIS=(core.state config.pacman_conf pkg.pacman system.chroot)

run_stage() {
    debug_msg "Starting pacman configuration stage"
    status_msg "Configuring pacman with official repositories..."

    pacman_conf::enable_multilib "$TARGET_MNT" || return 1
    pacman_conf::chaotic_aur_enable "$TARGET_MNT" || return 1
    pacman_conf::eyecandy "$TARGET_MNT" || return 1
    pacman_conf::refresh "$TARGET_MNT" || return 1

    state_set "aur/chaotic" "enabled"
    success_msg "Pacman repositories configured and databases refreshed"
    return 0
}
