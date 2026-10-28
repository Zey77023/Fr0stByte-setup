#!/bin/bash

# stage 09 — locale: locale selection and configuration
# Also configures vconsole.conf

STAGE_ID="09-locale"
STAGE_KIND="interactive"
STAGE_DESC="Locale generation and configuration on the target with vconsole.conf configuration"
STAGE_APIS=(core.state config.locale system.chroot)

run_stage() {
    lc_pick_locale() {
        local -a available_locales
        locale::available available_locales "$TARGET_MNT" || return 1

        $(printf '%s\n' "${available_locales[@]}" \
            | ui::filter --no-limit --height 10 \
            --header="Select locales to generate (Tab to toggle, Enter to confirm)")
    }

    debug_msg "Starting locale configuration stage"
    status_msg "Locale generation and configuration..."

    local keyboard_layout
    keyboard_layout=$(state_get keyboard/layout)

    local selection
    local -a selected_locales=()
    local default_seed
    local default_locale

    default_seed=$(defaults::get defaults_locale) || {
        error_msg "defaults_locale missing from the config registry"
        return 1
    }

    if [[ -n "$default_seed" ]]; then
        status_msg "profile: defaults_locale='$default_seed' (configured)"
        read -ra selected_locales <<<"$default_seed"
        selected_locales=(${selected_locales[@]})
        default_locale="${selected_locales[0]}"
    else
        while true; do
            if selection=$(lc_pick_locale); then
                mapfile -t selected_locales <<<"$selection"
                selected_locales=(${selected_locales[@]})
            fi

            if [[ ${#selected_locales[@]} -eq 0 ]]; then
                selected_locales=("en_US.UTF-8")
            fi

            if ! ui:confirm defaults_locale \
                "Use selected locales {${selected_locales[*]}} to be generated for the installed system?" yes; then
                status_msg "Locale generation configuration rejected by user; Try again or (Ctrl + C) to exit the installer"
                else break
            fi
        done
    fi

    debug_msg "Selected locales: ${selected_locales[*]}"

    if [[ -z "$default_locale" ]]; then
        while true; do
            default_locale=$(printf '%s\n' "${selected_locales[@]}" \
                | ui::filter --height 10 \
                    --header="Select default locale (LANG) for the system")

            default_locale="${default_locale:-${selected_locales[0]}}"

            if ! ui::confirm locale_default_confirm \
                "User selected locale '$default_locale' as the default locale for the installed system?" yes; then
                status_msg "Default locale configuration rejected by user; Try again or (Ctrl + C) to exit the installer"
                else break
            fi
        done
    fi

    debug_msg "Default locale chosen: $default_locale"

    locale::locale_set "$TARGET_MNT" selected_locales \
        "$default_locale" "$keyboard_layout" || return 1

    state_set "locale/default" "$default_locale"

    success_msg "Locales generated: ${selected_locales[*]}"
    success_msg "Default system locale (LANG) set to: $default_locale"
    success_msg "Keyboard layout '$keyboard_layout' written to vconsole.conf"
    return 0
}
