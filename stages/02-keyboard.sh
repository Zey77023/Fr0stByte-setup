#!/bin/bash

# stage 02 — keyboard: interactive layout selection.

STAGE_ID="02-keyboard"
STAGE_KIND="interactive"
STAGE_DESC="Keyboard layout selection"
STAGE_APIS=(core.state)

run_stage() {
    kb_pick_layout() {
        localectl list-keymaps | ui::filter --height 10 \
            --placeholder "Search or select your layout..."
    }

    status_msg "Configuring keyboard layout..."

    local layout
    local default_seed

    default_seed=$(defaults::get defaults_layout) || {
        error_msg "defaults_layout missing from the config registry"
        return 1
    }

    if [[ -n "$default_seed" ]]; then
        status_msg "profile: defaults_layout='$default_seed' (configured)"
        layout="$default_seed"
    else
        while true; do
            layout=$(kb_pick_layout)
            layout="${layout:-us}"

            if ! ui::confirm defaults_layout \
                "User layout '$layout' for the installed system?" yes; then
                status_msg "Layout configuration rejected by user; Try again or (Ctrl + C) to exit installer"
                else break
            fi
        done
    fi

    debug_msg "User selected keyboard layout: $layout"
    state_set "keyboard/layout" "$layout"
    exec_cmd loadkeys "$layout"
    success_msg "Layout set to: $layout"

    return 0
}
