#!/bin/bash

# Pacman invocation APIs

if [[ ${_SOURCED_pkg_pacman:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_pkg_pacman="loaded"

module::provide pkg.pacman pacman::sync pacman::host_install pacman::target \
    pacman::key_import pkg::is_installed

# pacman::sync — host-side `pacman -Sy --noconfirm`.
pacman::sync() {
    ui::spin "Updating package databases..." -- pacman -Sy --noconfirm
}

# pacman::host_install <packages[@]> — host-side `pacman -S --needed --noconfirm`.
pacman::host_install() {
    (($# > 0)) || {
        warn_msg "No packages selected for host install"
        return 0
    }
    ui::spin "Installing packages..." -- pacman -S --needed --noconfirm "$@"
}

# pacman::target <mnt> <args…> — arbitrary pacman invocation inside <mnt>.
pacman::target() {
    local mnt="$1"
    shift
    (($# > 0)) || {
        warn_msg "pacman::target called without arguments"
        return 0
    }
    chroot_exec "$mnt" --expect "0" -- pacman "$@"
}

# pacman::key_import <mnt> <key> <keyserver> — import + lsign
pacman::key_import() {
    local mnt="$1" key="$2" keyserver="$3"

    if [ ! -d "$mnt/etc/pacman.d/gnupg/openpgp-revocs.d" ]; then
        ui::spin "Initializing pacman keyring in target..." \
            -- chroot_exec "$mnt" -- pacman-key --init || return 1
        ui::spin "Populating default pacman keyring..." \
            -- chroot_exec "$mnt" -- pacman-key --populate archlinux || return 1
    fi

    ui::spin "Importing GPG key $key..." \
        -- chroot_exec "$mnt" -- pacman-key --recv-key "$key" --keyserver "$keyserver" \
        || return 1
    ui::spin "Signing GPG key $key locally..." \
        -- chroot_exec "$mnt" -- pacman-key --lsign-key "$key" || return 1
    return 0
}

# pkg::is_installed <mnt> <pkg> - rc 0=installed, 1=not, 2=query error.
pkg::is_installed() {
    local mnt="$1" pkg="$2" rc=0
    chroot_exec "$mnt" --expect "0 1" --code rc -- pacman -Q "$pkg" || {
        error_msg "pkg::is_installed: pacman -Q failed unexpectedly for $pkg"
        return 2
    }
    [[ "$rc" == "0" ]]
}
