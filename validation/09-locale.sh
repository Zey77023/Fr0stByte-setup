#!/bin/bash

# validation/09-locale —
# pre: keyboard layout in state and the target's locale.gen present
# post: locale/default present and /etc/locale.conf + /etc/vconsole.conf in target
# have the expected values

VALIDATE_APIS=(validation.core.check core.state)

validate::09_locale() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            check::require_state "keyboard/layout" "09-locale" || return 1

            if check::is_dryrun; then
                debug_msg "validation 09 pre: dry-run; locale.gen check skipped"
                return 0
            fi

            check::require_file "$mnt/etc/locale.gen" || return 1
            ;;
        post)
            check::require_state "locale/default" "09-locale" || return 1

            if check::is_dryrun; then
                debug_msg "validation 09 post: dry-run; file assertions skipped"
                return 0
            fi

            local lang keymap
            lang="$(state_get locale/default)"
            keymap="$(state_get keyboard/layout)"

            if ! [[ -f "$mnt/etc/locale.conf" ]] \
                || ! grep -Fxq "LANG=$lang" "$mnt/etc/locale.conf"; then
                check::fail "/etc/locale.conf does not set LANG=$lang"
                return 1
            fi

            if ! [[ -f "$mnt/etc/vconsole.conf" ]] \
                || ! grep -Fxq "KEYMAP=$keymap" "$mnt/etc/vconsole.conf"; then
                check::fail "/etc/vconsole.conf does not set KEYMAP=$keymap"
                return 1
            fi
            ;;
        *)
            error_msg "validation 09: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
