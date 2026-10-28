#!/bin/bash

# validation/08-localtime —
# pre: the host can produce a timezone list
# post: timezone/name journaled and the target's /etc/localtime + /etc/timezone
# reflect expected values

VALIDATE_APIS=(validation.core.check core.state)

validate::08_localtime() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            if check::is_dryrun; then
                debug_msg "validation 08 pre: dry-run; timedatectl check skipped"
                return 0
            fi
            if ! timedatectl list-timezones 2>/dev/null | grep -q '[^[:space:]]'; then
                check::fail "timedatectl produced no timezone list"
                return 1
            fi
            ;;
        post)
            check::require_state "timezone/name" "08-localtime" || return 1
            if check::is_dryrun; then
                debug_msg "validation 08 post: dry-run; file assertions skipped"
                return 0
            fi
            local tz
            tz="$(state_get timezone/name)"
            check::require_file "$mnt/etc/localtime" || return 1
            if ! [[ "$(readlink "$mnt/etc/localtime")" == "/usr/share/zoneinfo/$tz" ]]; then
                check::fail "/etc/localtime does not point at /usr/share/zoneinfo/$tz"
                return 1
            fi
            if ! [[ -f "$mnt/etc/timezone" ]] \
                || ! grep -Fxq "$tz" "$mnt/etc/timezone"; then
                check::fail "/etc/timezone does not contain: $tz"
                return 1
            fi
            ;;
        *)
            error_msg "validation 08: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
