#!/bin/bash

# validation/16-snapper —
# pre: stage-05 mounts/done always, plus the
# read-only chroot probe that /.snapshots is backed by the dedicated
# @snapshots subvolume
# post: snapper/configured state, the
# config carries the shipped retention values and the /etc/conf.d
# registration is in place. The snapper timers warnings if unable to enable

VALIDATE_APIS=(validation.core.check core.state system.chroot)

validate::16_snapper() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            check::require_state "mounts/done" "16-snapper" || return 1
            if check::is_dryrun; then
                debug_msg "validation 16 pre: dry-run; @snapshots probe skipped"
                return 0
            fi
            local source
            source="$(chroot_exec "$mnt" -- findmnt -n -o SOURCE -T /.snapshots)" || {
                check::fail "could not read the /.snapshots mount source"
                return 1
            }
            [[ "$source" == *"@snapshots"* ]] || {
                check::fail "/.snapshots is not backed by the dedicated @snapshots subvolume: $source"
                return 1
            }
            ;;
        post)
            check::require_state "snapper/configured" "16-snapper" || return 1
            if check::is_dryrun; then
                debug_msg "validation 16 post: dry-run; file assertions skipped"
                return 0
            fi
            local conf="$mnt/etc/snapper/configs/root"
            check::require_file "$conf" || return 1
            local -a expected=(
                'SUBVOLUME="/"'
                'TIMELINE_CREATE="no"'
                'TIMELINE_CLEANUP="yes"'
                'TIMELINE_LIMIT_HOURLY="0"'
                'TIMELINE_LIMIT_DAILY="0"'
                'TIMELINE_LIMIT_WEEKLY="10"'
                'TIMELINE_LIMIT_MONTHLY="10"'
                'TIMELINE_LIMIT_YEARLY="10"'
                'NUMBER_LIMIT="20"'
                'NUMBER_LIMIT_IMPORTANT="10"'
            )
            local row
            for row in "${expected[@]}"; do
                grep -Fqx "$row" "$conf" || {
                    check::fail "snapper config missing retention row: $row"
                    return 1
                }
            done
            check::require_file "$mnt/etc/conf.d/snapper" || return 1
            grep -Fqx 'SNAPPER_CONFIGS="root"' "$mnt/etc/conf.d/snapper" || {
                check::fail "snapper is not registered in /etc/conf.d/snapper"
                return 1
            }
            ;;
        *)
            error_msg "validation 16: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
