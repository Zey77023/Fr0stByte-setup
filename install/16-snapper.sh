#!/bin/bash

debug_msg "Starting Snapper configuration stage"

status_msg "Configuring Snapper for Btrfs snapshots..."

debug_msg "Installing snapper package"
chroot_exec pacman -S --needed --noconfirm snapper
success_msg "Snapper installed"

SNAPPER_CONF="$TARGET_MNT/etc/snapper/configs/root"
status_msg "Validating the dedicated @snapshots mount..."
SNAPSHOT_SOURCE=$(chroot_exec findmnt -n -o SOURCE -T /.snapshots)
[[ "$SNAPSHOT_SOURCE" == *"@snapshots"* ]] || {
    error_msg "/.snapshots is not backed by the dedicated @snapshots subvolume"
    exit 1
}

# Build the config directly so snapper does not create a second .snapshots
# subvolume over the one created during disk setup.
status_msg "Creating Snapper configuration for the existing snapshots mount..."
chroot_exec mkdir -p /etc/snapper/configs
chroot_exec cp /usr/share/snapper/config-templates/default /etc/snapper/configs/root

[[ -f "$SNAPPER_CONF" ]] || {
    error_msg "Snapper config was not created at $SNAPPER_CONF"
    exit 1
}

sed -i 's|^SUBVOLUME=.*|SUBVOLUME="/"|' "$SNAPPER_CONF"
sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' "$SNAPPER_CONF"
sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' "$SNAPPER_CONF"
sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/' "$SNAPPER_CONF"
sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="0"/' "$SNAPPER_CONF"
sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="10"/' "$SNAPPER_CONF"
sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="10"/' "$SNAPPER_CONF"
sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="10"/' "$SNAPPER_CONF"
sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="20"/' "$SNAPPER_CONF"
sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' "$SNAPPER_CONF"

# Register with Snapper's list of configs
SNAPPER_CONFD="$TARGET_MNT/etc/conf.d/snapper"
mkdir -p "$(dirname -- "$SNAPPER_CONFD")"
printf '%s\n' 'SNAPPER_CONFIGS="root"' >"$SNAPPER_CONFD"

# Set TERM only for Snapper so the installer's environment is unchanged.
chroot_exec env TERM=xterm-256color snapper --no-dbus -c root list
TEST_SNAPSHOT=$(chroot_exec env TERM=xterm-256color snapper --no-dbus -c root create --print-number --description "Fr0stByte snapshot validation")
[[ "$TEST_SNAPSHOT" =~ ^[0-9]+$ ]] || {
    error_msg "Snapper did not return a valid test snapshot number"
    exit 1
}
chroot_exec env TERM=xterm-256color snapper --no-dbus -c root list
chroot_exec env TERM=xterm-256color snapper --no-dbus -c root delete "$TEST_SNAPSHOT"
success_msg "Snapper configured against @snapshots"

# Enable timers
chroot_exec --expect "0 1 2" systemctl enable snapper-timeline.timer
if [[ $CHROOT_EXEC_EXIT_CODE -ne 0 ]]; then
    warn_msg "snapper-timeline.timer could not be enabled"
fi
chroot_exec --expect "0 1 2" systemctl enable snapper-cleanup.timer
if [[ $CHROOT_EXEC_EXIT_CODE -ne 0 ]]; then
    warn_msg "snapper-cleanup.timer could not be enabled"
fi

# snap-pac is optional; the base installer remains usable without it.
if gum confirm "Enable automatic Snapper snapshots for pacman transactions?" --default=no; then
    chroot_exec --expect "0 1" pacman -Si snap-pac
    if [[ $CHROOT_EXEC_EXIT_CODE -ne 0 ]]; then
        warn_msg "snap-pac is unavailable in the enabled repositories; skipping it"
    else
        chroot_exec pacman -S --needed --noconfirm snap-pac
        success_msg "snap-pac installed for pacman transaction snapshots"
    fi
else
    status_msg "snap-pac disabled; pacman transactions will not create automatic snapshots"
fi

success_msg "Snapshot cleanup and timeline services configured"
