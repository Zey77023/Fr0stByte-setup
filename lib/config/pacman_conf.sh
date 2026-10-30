#!/bin/bash

# pacman.conf management: multilib,
# Chaotic-AUR, eye-candy, and the final official-repo refresh.

if [[ ${_SOURCED_config_pacman_conf:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_pacman_conf="loaded"

module::provide config.pacman_conf pacman_conf::enable_multilib \
    pacman_conf::chaotic_aur_enable pacman_conf::eyecandy pacman_conf::refresh

# pacman_conf::__gate <conf> — check presence of pacman.conf.
pacman_conf::__gate() {
    [[ -f $1 ]] && return 0
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: target pacman.conf absent; add-if-absent reads canonical"
        return 0
    fi
    error_msg "Target pacman.conf missing: $1"
    return 1
}

# pacman_conf::enable_multilib <mnt> — uncomment the [multilib] block.
pacman_conf::enable_multilib() {
    local conf="$1/etc/pacman.conf"
    pacman_conf::__gate "$conf" || return 1
    exec_cmd sed -i '/\[multilib\]/,/Include/s/^#//' "$conf" || return 1
    return 0
}

# pacman_conf::chaotic_aur_enable <mnt> - add chaotic aur to the repo list.
pacman_conf::chaotic_aur_enable() {
    local mnt="$1"
    local conf="$mnt/etc/pacman.conf"
    local key="3056513887B78AEB"

    pacman_conf::__gate "$conf" || return 1

    status_msg "Configuring pacman with Chaotic-AUR"
    pacman::key_import "$mnt" "$key" keyserver.ubuntu.com || return 1
    ui::spin "Installing Chaotic-AUR keyring and mirrorlist..." \
        -- chroot_exec "$mnt" -- pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' \
        || return 1

    if ! grep -q '^\[chaotic-aur\]' "$conf" 2>/dev/null; then
        exec_cmd tee -a "$conf" >/dev/null <<EOS

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOS
    fi

    ui::spin "Refreshing Chaotic-AUR databases..." \
        -- chroot_exec "$mnt" -- pacman -Syu --noconfirm || return 1
    return 0
}

# pacman_conf::eyecandy <mnt> — ILoveCandy + VerbosePkgLists in [options].
pacman_conf::eyecandy() {
    local conf="$1/etc/pacman.conf"
    pacman_conf::__gate "$conf" || return 1
    grep -q '^ILoveCandy$' "$conf" 2>/dev/null \
        || exec_cmd sed -i '/^\[options\]/a ILoveCandy' "$conf" \
        || return 1
    grep -q '^VerbosePkgLists$' "$conf" 2>/dev/null \
        || exec_cmd sed -i '/^\[options\]/a VerbosePkgLists' "$conf" \
        || return 1
    return 0
}

# pacman_conf::refresh <mnt> - repo full sync
pacman_conf::refresh() {
    ui::spin "Refreshing official repositories..." \
        -- chroot_exec "$1" -- pacman -Syu --noconfirm
}

return 0
