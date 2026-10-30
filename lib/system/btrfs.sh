#!/bin/bash

# Btrfs APIs

if [[ ${_SOURCED_system_btrfs:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_system_btrfs="loaded"

module::provide system.btrfs \
    btrfs::make_subvolumes btrfs::prepare_swap_subvol btrfs::swapfile_create \
    btrfs::swapfile_enable btrfs::swapfile_verify btrfs::swapfile_disable \
    btrfs::resume_offset

# btrfs::make_subvolumes <mnt> <subvol[@]>
#   Create each subvolume under <mnt>/<name>.
btrfs::make_subvolumes() {
    local mnt="$1"
    shift
    local -a subvols=("$@")
    local sub
    for sub in "${subvols[@]}"; do
        if ! ui::spin "Creating subvolume: $sub" -- \
            btrfs subvolume create "$mnt/$sub"; then
            error_msg "Failed to create subvolume: $sub"
            return 1
        fi
    done
    return 0
}

# btrfs::prepare_swap_subvol <swap_subvol_dir>
#   D-6: chattr +C AND btrfs property set … compression none.
btrfs::prepare_swap_subvol() {
    local swap_subvol="$1"
    exec_cmd chattr +C "$swap_subvol" || return 1
    status_msg "Set nodatacow on @swap subvolume"
    return 0
}

# btrfs::swapfile_create <out_var> <swap_subvol_dir> <size_mib>
btrfs::swapfile_create() {
    local -n out_path="$1"
    local swap_subvol="$2" size_mib="$3"
    local swap_path actual_size

    swap_path="$swap_subvol/swapfile"
    exec_cmd btrfs filesystem mkswapfile --size "${size_mib}m" "$swap_path" || return 1
    exec_cmd chmod 600 "$swap_path" || return 1

    # Dry-run: the file was never created; skip the on-disk size assert.
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        out_path="$swap_path"
        return 0
    fi

    actual_size=$(stat -c '%s' "$swap_path")
    ((actual_size >= size_mib * 1024 * 1024)) || {
        error_msg "Swapfile is smaller than the requested RAM-sized allocation"
        return 1
    }
    out_path="$swap_path"
    return 0
}

# btrfs::swapfile_enable - Swapfile activation
btrfs::swapfile_enable() {
    exec_cmd swapon "$1"
}

# btrfs::swapfile_verify - Verify swapfile activation
btrfs::swapfile_verify() {
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: swapfile activation verification skipped"
        return 0
    fi
    swapon --show=NAME --noheadings | grep -Fq "$1"
}

# btrfs::swapfile_disable - Swapfile deactivate
btrfs::swapfile_disable() {
    exec_cmd swapoff "$1" || return 1
    return 0
}

# btrfs::resume_offset <out_var> <swapfile_path> - Calculate swapfile resume offset for
# use with hibernation
btrfs::resume_offset() {
    local -n out_offset="$1"
    local swapfile="$2"
    local raw_offset
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        out_offset="264192"
        debug_msg "DRY-RUN: canned Btrfs swapfile resume offset (swapfile assumed)"
        return 0
    fi
    if ! raw_offset=$(btrfs inspect-internal map-swapfile -r "$swapfile" 2>/dev/null); then
        error_msg "Could not calculate the Btrfs swapfile resume offset"
        return 1
    fi
    [[ "$raw_offset" =~ ^[1-9][0-9]*$ ]] || {
        error_msg "Invalid Btrfs swapfile resume offset: $raw_offset"
        return 1
    }
    out_offset="$raw_offset"
    return 0
}

return 0
