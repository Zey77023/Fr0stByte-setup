#!/bin/bash

# stage 05 — disk setup: partition (AUTO), LUKS2 encryption, Btrfs
# subvolumes, RAM-sized swapfile, and the /mnt hierarchy.

STAGE_ID="05-disk-setup"
STAGE_KIND="destructive"
STAGE_DESC="Partition the target, LUKS2-encrypt, format Btrfs, subvolumes + swapfile, mount /mnt hierarchy"
STAGE_APIS=(core.state core.secret system.disk system.luks system.btrfs system.mounts)

run_stage() {
    debug_msg "Starting disk formatting and mounting stage"
    status_msg "Starting Disk Formatting and Mounting..."
    debug_msg "Mount options: $_MOUNTS_BTRFS_OPTS"

    local st_disk st_mode st_boot="" st_root=""
    local st_luks_name st_luks_uuid st_swap_path st_mapper
    local -a st_subvols=( "@" "@home" "@var_log" "@var_cache" "@snapshots" "@swap" )
    local -a st_mntpts=(
        "$TARGET_MNT" "$TARGET_MNT/home" "$TARGET_MNT/var/log"
        "$TARGET_MNT/var/cache" "$TARGET_MNT/.snapshots" "$TARGET_MNT/swap"
    )

    st_disk="$(state_get partition/disk)"
    st_mode="$(state_get partition/mode)"
    st_luks_name="$(state_get luks/name "${LUKS_NAME:-cryptroot}")"
    state_set "luks/name" "$st_luks_name"
    st_mapper="/dev/mapper/${st_luks_name}"

    if [[ "$st_mode" == "AUTO" ]] && ! state_has "luks/formatted"; then
        disk::partition_auto "$st_disk" "$BOOT_LABEL" "$ROOT_LABEL" st_boot st_root || return 1
        state_set "partition/boot" "$st_boot"
        state_set "partition/root" "$st_root"
    fi

    st_boot="$(state_get partition/boot)"
    st_root="$(state_get partition/root)"
    [[ -n "$st_boot" && -n "$st_root" ]] || {
        error_msg "partition/boot and partition/root are required"
        return 1
    }

    local st_need_format=1 st_need_open=1 st_passfile=""
    if state_has "luks/formatted"; then
        st_need_format=0
    fi
    if state_has "luks/opened"; then
        st_need_open=0
    fi

    if (( st_need_format )); then
        status_msg "Setting up LUKS encryption on $st_root"
        secret::request "LUKS" st_passfile || return 1
        if ! luks::format "$st_root" "$st_passfile"; then
            secret::shred "$st_passfile"
            error_msg "LUKS formatting failed"
            return 1
        fi
        state_set "luks/formatted" "done"
    fi

    if (( st_need_open )); then
        if [[ -z "$st_passfile" ]]; then
            secret::request "LUKS" st_passfile || return 1
        fi
        if ! luks::open "$st_root" "$st_luks_name" "$st_passfile"; then
            secret::shred "$st_passfile"
            error_msg "Could not open the newly formatted LUKS container"
            return 1
        fi
        secret::shred "$st_passfile"
        state_set "luks/opened" "done"
        debug_msg "LUKS setup complete"
    fi

    luks::uuid st_luks_uuid "$st_root" || return 1
    state_set "luks/uuid" "$st_luks_uuid"
    debug_msg "LUKS UUID: $st_luks_uuid"

    status_msg "Creating Btrfs Subvolumes..."
    debug_msg "Subvolumes to create: ${st_subvols[*]}"

    if ! state_has "sv/created"; then
        ui::spin "Formatting Boot ($st_boot)..." -- mkfs.fat -F32 "$st_boot" || return 1
        debug_msg "Formatting boot partition: $st_boot (FAT32)"
        ui::spin "Formatting Root ($st_mapper)..." -- mkfs.btrfs -f "$st_mapper" || return 1
        debug_msg "Formatting root partition: $st_mapper (Btrfs)"

        if [[ ${FR0ST_DRYRUN:-0} == "1" ]] || ! mountpoint -q "$TARGET_MNT"; then
            ui::spin "Mounting Btrfs root for staging at $TARGET_MNT" -- \
                mount "$st_mapper" "$TARGET_MNT" || return 1
            mounts::register "$TARGET_MNT"
        else
            debug_msg "staging mount already present; reusing it"
        fi
        btrfs::make_subvolumes "$TARGET_MNT" "${st_subvols[@]}" || return 1
        btrfs::prepare_swap_subvol "$TARGET_MNT/@swap" || return 1
        state_set "sv/created" "done"
    fi

    if ! state_has "swap/created"; then
        if [[ ${FR0ST_DRYRUN:-0} != "1" ]] && ! mountpoint -q "$TARGET_MNT" 2>/dev/null; then
            warn_msg "staging mount missing on resume; re-attaching"
            ui::spin "Re-attaching Btrfs root for staging at $TARGET_MNT" -- \
                mount "$st_mapper" "$TARGET_MNT" || return 1
            mounts::register "$TARGET_MNT"
        fi

        local st_total_ram_kb st_swap_mib st_swap_gib=0
        st_total_ram_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
        (( st_swap_gib = (st_total_ram_kb + 1048575) / 1048576 ))
        st_swap_mib=$(( st_swap_gib * 1024 ))
        debug_msg "Total RAM: ${st_total_ram_kb}KB, Swap size: ${st_swap_mib}MB"
        status_msg "Creating swap file (${st_swap_mib}MB) for hibernation..."
        btrfs::swapfile_create st_swap_path "$TARGET_MNT/@swap" "$st_swap_mib" || return 1
        btrfs::swapfile_enable "$st_swap_path" || return 1

        if ! btrfs::swapfile_verify "$st_swap_path"; then
            btrfs::swapfile_disable "$st_swap_path" || true
            error_msg "Swapfile could not be activated for verification"
            return 1
        fi

        btrfs::swapfile_disable "$st_swap_path" || return 1
        success_msg "Swap file created at /swap/swapfile"
        state_set "swap/file" "/swap/swapfile"
        state_set "swap/created" "done"
    fi

    if ! state_has "mounts/done"; then
        if [[ ${FR0ST_DRYRUN:-0} == "1" ]] || mountpoint -q "$TARGET_MNT"; then
            ui::spin "Unmounting staging root from $TARGET_MNT" -- umount "$TARGET_MNT" || return 1
        else
            debug_msg "staging mount already gone; skipping the umount"
        fi

        status_msg "Mounting filesystems..."
        mounts::mount_subvolumes "$st_mapper" st_subvols st_mntpts || return 1
        mounts::mount_esp "$st_boot" "$TARGET_MNT" || return 1

        if [[ "$(defaults::get luks_header_backup)" == "yes" ]]; then
            local st_header_file
            luks::header_backup st_header_file "$st_root" "$TARGET_MNT/boot" \
                || return 1
            state_set "luks/header_backup" "$st_header_file"
            success_msg "LUKS header backup stored on the ESP: $st_header_file"
            warn_msg "Copy the header backup to external media — it is the only recovery path for damaged LUKS header sectors"
        fi
        state_set "mounts/done" "done"
    fi

    success_msg "Disk setup complete. Hierarchy mounted at $TARGET_MNT"
    return 0
}
