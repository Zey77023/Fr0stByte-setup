#!/bin/bash

# Mount APIs

if [[ ${_SOURCED_system_mounts:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_system_mounts="loaded"

module::provide system.mounts mounts::mount_subvolumes mounts::mount_esp mounts::register

# Default mount options for data subvolumes.
declare -gr _MOUNTS_BTRFS_OPTS="compress=zstd:1,noatime"

# mounts::mount_subvolumes <mapper_dev> <subvols_ref> <mntpts_ref> [opts]
mounts::mount_subvolumes() {
    local mapper_dev="$1"
    local -n subvols="$2"
    local -n mntpts="$3"
    local opts="${4:-$_MOUNTS_BTRFS_OPTS}"

    ((${#mntpts[@]} != 0)) || return 0
    if ((${#subvols[@]} != ${#mntpts[@]})); then
        error_msg "mounts::mount_subvolumes: subvol/mnt count mismatch " \
            "(${#subvols[@]} vs ${#mntpts[@]})"
        return 1
    fi

    local i sub target
    for i in "${!mntpts[@]}"; do
        sub="${subvols[$i]}"
        target="${mntpts[$i]}"
        target="${target//\/\//\/}"   # collapse doubled slashes
        if mountpoint -q "$target" 2>/dev/null; then
            debug_msg "mounts: $target already mounted; registering only"
            mounts::register "$target"
            continue
        fi
        if ! ui::spin "Mounting $sub to $target" -- \
            mount -o "$opts,subvol=$sub" --mkdir "$mapper_dev" "$target"; then
            return 1
        fi
        mounts::register "$target"
    done
    return 0
}

# mounts::mount_esp <boot_partition> <mnt>
mounts::mount_esp() {
    local boot_part="$1" mnt="$2"
    if mountpoint -q "$mnt/boot" 2>/dev/null; then
        debug_msg "mounts: $mnt/boot already mounted; registering only"
        mounts::register "$mnt/boot"
        return 0
    fi
    ui::spin "Mounting ESP" -- mount --mkdir "$boot_part" "$mnt/boot" || return 1
    mounts::register "$mnt/boot"
    return 0
}

# mounts::register <mountpoint> — state broker wrap.
mounts::register() {
    register_mount "$1"
}

return 0
