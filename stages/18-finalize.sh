#!/bin/bash

# stage 18 — finalize: show installation summary, backup luks header to ESP,
# copy installation log to target and finally present the user with options to
# reboot, exit to chroot or exit to shell

STAGE_ID="18-finalize"
STAGE_KIND="interactive"
STAGE_DESC="Installation summary, log copy and the final next-action prompt"
STAGE_APIS=(
    core.state core.ui
    system.chroot
)

run_stage() {
    debug_msg "Starting finalization stage"

    local st_profile
    st_profile="$(sed -n 's/^PROFILE_\([^=]*\)="enabled"/\1/p' \
        "$TARGET_MNT/etc/fr0stbyte/performance.conf" 2>/dev/null \
        | tr '\n' ',' | sed 's/,$//' || true)"

    status_msg "Installation Summary"
    status_msg "─────────────────────────────────"
    status_msg "Hostname      : $(state_get hosts/hostname "unknown")"
    status_msg "User          : $(state_get users/user "none")"
    status_msg "Timezone      : $(state_get timezone/name "unknown")"
    status_msg "Locale        : $(state_get locale/default "unknown")"
    status_msg "Disk          : $(state_get partition/disk "unknown")"
    status_msg "Encryption    : LUKS2 on root"
    status_msg "Filesystem    : Btrfs with subvolumes"
    status_msg "Bootloader    : Limine"
    status_msg "Performance   : ${st_profile:-default}"
    status_msg "─────────────────────────────────"
    status_msg "Log file saved to: ${LOG_FILE}"

    local st_header
    st_header="$(state_get luks/header_backup "")"
    if [[ -n "$st_header" ]]; then
        status_msg "LUKS header backup reminder: $st_header — copy it to external media"
    fi

    exec_cmd mkdir -p "$TARGET_MNT/var/log" || true
    if exec_cmd cp "$LOG_FILE" "$TARGET_MNT/var/log/fr0stbyte-install.log"; then
        success_msg "Install log copied to /var/log/fr0stbyte-install.log in target system"
    else
        warn_msg "Could not copy the install log into the target system"
    fi
    if [[ ${FR0ST_TRACE:-0} == "1" ]]; then
        if exec_cmd cp "$TRACE_LOG_FILE" \
            "$TARGET_MNT/var/log/fr0stbyte-install.trace.log"; then
            success_msg "Trace log copied to /var/log/fr0stbyte-install.trace.log in target system"
        else
            warn_msg "Could not copy the trace log into the target system"
        fi
    fi

    local st_next
    st_next="$(ui::choose "Installation complete. What would you like to do?" \
        "Reboot now" \
        "Chroot into system" \
        "Exit to shell")"

    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: final action '${st_next:-<none>}' recorded, not executed (§8.2)"
        return 0
    fi

    case "$st_next" in
        "Reboot now")
            status_msg "Unmounting filesystems..."
            cleanup_target "$TARGET_MNT"
            success_msg "Unmounted. Rebooting..."
            reboot
            ;;
        "Chroot into system")
            status_msg "Dropping into chroot. Type 'exit' when done"
            arch-chroot "$TARGET_MNT"
            status_msg "Exited chroot"
            ;;
        *)
            status_msg "Exiting installer. Filesystems remain mounted at $TARGET_MNT"
            ;;
    esac
    return 0
}
