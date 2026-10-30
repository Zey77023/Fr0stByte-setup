#!/bin/bash
# validation/07-fstab —
# pre: the mount hierarchy exists
# post: the fstab file was written and verified

VALIDATE_APIS=(validation.core.check core.state)

validate::07_fstab() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            check::require_state "mounts/done" "07-fstab" || return 1
            if check::is_dryrun; then
                debug_msg "validation 07 pre: dry-run; mount-table check skipped"
                return 0
            fi
            findmnt -rn "$mnt" >/dev/null 2>&1 || {
                check::fail "no mounted filesystem under: $mnt"
                return 1
            }
            ;;
        post)
            check::require_state "fstab/verified" "07-fstab" || return 1
            if check::is_dryrun; then
                debug_msg "validation 07 post: dry-run; file assertions skipped"
                return 0
            fi
            check::require_file "$mnt/etc/fstab" || return 1
            if ! grep -qE '^[[:space:]]*[^#[:space:]]' "$mnt/etc/fstab"; then
                check::fail "generated fstab is empty: $mnt/etc/fstab"
                return 1
            fi
            ;;
        *)
            error_msg "validation 07: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
