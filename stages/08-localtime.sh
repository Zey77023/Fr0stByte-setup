#!/bin/bash

# stage 08 — localtime: timezone selection and configuration

STAGE_ID="08-localtime"
STAGE_KIND="interactive"
STAGE_DESC="Timezone selection and localtime configuration on the target"
STAGE_APIS=(core.state config.timezone)

run_stage() {
    lt_pick_tz() {
        $(printf '%s\n' "$(timedatectl list-timezones 2>/dev/null)"\
            | ui::filter --height 10 \
            --placeholder "Search or select your timezone..." \
            --value "$default_tz")
    }

    debug_msg "Starting timezone configuration stage"
    status_msg "Timezone / localtime configuration..."

    local tz
    local default_tz

    default_tz=$(defaults::get defaults_timezone) || {
        error_msg "defaults_timezone missing from the config registry"
        return 1
    }

    if [[ -n "$default_tz" ]]; then
        status_msg "profile: defaults_timezone='$default_tz' (configured)"
        tz="$default_tz"
    else
        while true; do
            tz=$(lt_pick_tz)
            tz="${tz:-Asia/Kolkata}"

            if ! ui::confirm defaults_timezone \
                "Use timezone '$tz' for the installed system?" yes; then
                status_msg "Timezone configuration rejected by user; Try again or (Ctrl + C) to exit installer"
                else break
            fi
        done
    fi

    debug_msg "User selected timezone: $tz"
    timezone::timezone_set "$TARGET_MNT" "$tz" || return 1
    state_set "timezone/name" "$tz"
    success_msg "Timezone set to '$tz'"

    return 0
}
