#!/bin/bash

debug_msg "Starting keyboard layout stage"

status_msg "Configuring keyboard layout..."

# Obtain available keymaps and prompt user selection
MAPS=$(localectl list-keymaps)
KEYBOARD_LAYOUT=$(echo "$MAPS" | gum filter --height 10 \
    --placeholder "Search or select your layout..." --value "us")
KEYBOARD_LAYOUT=${KEYBOARD_LAYOUT:-us}

debug_msg "User selected keyboard layout: $KEYBOARD_LAYOUT"

# Load the selected keymap for current session
if gum confirm "Apply '$KEYBOARD_LAYOUT' to current session?"; then
    loadkeys "$KEYBOARD_LAYOUT"
    success_msg "Layout set to: $KEYBOARD_LAYOUT"
else
    status_msg "Layout configuration skipped"
fi
