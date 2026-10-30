#!/bin/bash
# Timezone APIs.

if [[ ${_SOURCED_config_timezone:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_timezone="loaded"

module::provide config.timezone timezone::timezone_set

# timezone::timezone_set <mnt> <tz>
#   zoneinfo sanity + localtime symlink + /etc/timezone + hwclock sync.
timezone::timezone_set() {
    local mnt="$1" tz="$2"
    local zoneinfo="$mnt/usr/share/zoneinfo/$tz"

    [[ "$tz" =~ ^[A-Za-z0-9_+/-]+$ ]] || {
        error_msg "Invalid timezone identifier: $tz"
        return 1
    }

    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: zoneinfo check skipped ($zoneinfo assumed present)"
    elif [[ ! -f "$zoneinfo" ]]; then
        error_msg "Zoneinfo file '$zoneinfo' not found"
        return 1
    fi
    exec_cmd ln -sf "/usr/share/zoneinfo/$tz" "$mnt/etc/localtime" || return 1
    exec_cmd tee "$mnt/etc/timezone" >/dev/null <<EOS
$tz
EOS

    if command -v arch-chroot &>/dev/null; then
        ui::spin "Syncing hardware clock" -- chroot_exec "$mnt" -- hwclock --systohc || return 1
    else
        status_msg "arch-chroot not available; skipping hwclock sync"
    fi
    return 0
}
