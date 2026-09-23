#!/bin/bash

debug_msg "Starting timezone configuration stage"

status_msg "Timezone / localtime configuration..."

# Get the list of available timezones
TIMEZONES=$(timedatectl list-timezones 2>/dev/null)
[[ -n "$TIMEZONES" ]] || { error_msg "Could not get timezone list from timedatectl"; exit 1; }

DEFAULT_TZ="${DEFAULT_TZ:-Asia/Kolkata}"
SELECTED_TZ=$(echo "$TIMEZONES" | gum filter --height 10 \
    --placeholder "Search or select your timezone..." --value "$DEFAULT_TZ")

SELECTED_TZ=${SELECTED_TZ:-$DEFAULT_TZ}
debug_msg "User selected timezone: $SELECTED_TZ"

# Confirm and set the timezone then sync the hardware clock
if gum confirm "Use timezone '$SELECTED_TZ' for the installed system?"; then
    ZONEINFO_PATH="/usr/share/zoneinfo/$SELECTED_TZ"
    [[ -f "$ZONEINFO_PATH" ]] || { error_msg "Zoneinfo file '$ZONEINFO_PATH' not found"; exit 1; }

    debug_msg "Setting timezone symlink: $ZONEINFO_PATH -> $TARGET_MNT/etc/localtime"
    ln -sf "$ZONEINFO_PATH" "$TARGET_MNT/etc/localtime"
    echo "$SELECTED_TZ" >"$TARGET_MNT/etc/timezone"

    if command -v arch-chroot &>/dev/null; then
        debug_msg "Syncing hardware clock"
        arch-chroot "$TARGET_MNT" hwclock --systohc
    else
        status_msg "arch-chroot not available; skipping hwclock sync"
    fi

    success_msg "Timezone set to '$SELECTED_TZ'"
else
    status_msg "Timezone configuration skipped"
fi
