#!/bin/bash

# validation/02-keyboard — pre: the layout chooser tool exists
# post: the preselection made it to the state broker

VALIDATE_APIS=(validation.core.check core.state)

validate::02_keyboard() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
                debug_msg "validation 02 pre: dry-run; tool assertions skipped"
                return 0
            fi
            if ! command -v localectl >/dev/null 2>&1; then
                check::fail "localectl is missing; cannot enumerate keymaps"
                return 1
            fi
            return 0
            ;;
        post)
            if ! check::require_state "keyboard/layout" "02-keyboard"; then
                return 1
            fi
            return 0
            ;;
        *)
            error_msg "validation 02: unknown mode '$mode'"
            return 2
            ;;
    esac
}

return 0
