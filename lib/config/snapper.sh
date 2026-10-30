#!/bin/bash

# Snapper setup + snapshot validation.

if [[ ${_SOURCED_config_snapper:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_snapper="loaded"

module::provide config.snapper snapper::setup snapper::roundtrip_validate snapper::timers

# snapper::setup <mnt>
#   Installs snapper, builds the config by hand (so snapper does not
#   create a second .snapshots subvolume over the one made during disk
#   setup), and registers SNAPPER_CONFIGS="root".
snapper::setup() {
    local mnt="$1"
    local conf="$mnt/etc/snapper/configs/root"

    pacman::target "$mnt" -S --needed --noconfirm snapper || return 1

    chroot_exec "$mnt" -- mkdir -p /etc/snapper/configs || return 1
    chroot_exec "$mnt" -- cp /usr/share/snapper/config-templates/default /etc/snapper/configs/root || return 1

    if [[ ${FR0ST_DRYRUN:-0} != "1" ]]; then
        [[ -f "$conf" ]] || {
            error_msg "Snapper config was not created at $conf"
            return 1
        }
    else
        debug_msg "DRY-RUN: snapper config assumed created (canonical)"
    fi

    exec_cmd sed -i 's|^SUBVOLUME=.*|SUBVOLUME="/"|' "$conf" || return 1
    exec_cmd sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' "$conf" || return 1
    exec_cmd sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' "$conf" || return 1
    exec_cmd sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/' "$conf" || return 1
    exec_cmd sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="0"/' "$conf" || return 1
    exec_cmd sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="10"/' "$conf" || return 1
    exec_cmd sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="10"/' "$conf" || return 1
    exec_cmd sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="10"/' "$conf" || return 1
    exec_cmd sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="20"/' "$conf" || return 1
    exec_cmd sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' "$conf" || return 1

    exec_cmd mkdir -p "$mnt/etc/conf.d" || return 1
    exec_cmd tee "$mnt/etc/conf.d/snapper" >/dev/null <<EOS
SNAPPER_CONFIGS="root"
EOS
    return 0
}

# snapper::roundtrip_validate <mnt> — list, create a numbered test
# snapshot, list again, delete it.
snapper::roundtrip_validate() {
    local mnt="$1" test_snapshot
    chroot_exec "$mnt" -- env TERM=xterm-256color snapper --no-dbus -c root list || return 1
    test_snapshot=$(chroot_exec "$mnt" -- env TERM=xterm-256color snapper --no-dbus -c root create --print-number --description "Fr0stByte snapshot validation") || test_snapshot=""
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: snapper roundtrip assumed (canonical snapshot number 1)"
        test_snapshot=1
    fi
    [[ "$test_snapshot" =~ ^[0-9]+$ ]] || {
        error_msg "Snapper did not return a valid test snapshot number"
        return 1
    }
    chroot_exec "$mnt" -- env TERM=xterm-256color snapper --no-dbus -c root list || return 1
    chroot_exec "$mnt" -- env TERM=xterm-256color snapper --no-dbus -c root delete "$test_snapshot" || return 1
    return 0
}

# snapper::timers <mnt> — enable timeline+cleanup timers.
# This does not guarantee enablement of the services and will print warnings if something unexpected happens.
# Returns non-zero only when a chroot call itself failed unexpectedly.
snapper::timers() {
    local mnt="$1" ok=1
    chroot_exec "$mnt" --expect "0 1 2" -- systemctl enable snapper-timeline.timer || ok=0
    chroot_exec "$mnt" --expect "0 1 2" -- systemctl enable snapper-cleanup.timer || ok=0
    (( ok == 1 ))
}

return 0
