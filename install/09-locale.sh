#!/bin/bash

debug_msg "Starting locale configuration stage"

status_msg "Locale generation and configuration..."

LOCALE_GEN="$TARGET_MNT/etc/locale.gen"
DEFAULT_LOCALE="${DEFAULT_LOCALE:-en_US.UTF-8}"

require_paths "$LOCALE_GEN"

# Collect all locales from the target's locale.gen
mapfile -t AVAILABLE_LOCALES < <(
    awk '/^[#[:space:]]*[a-zA-Z]+_[a-zA-Z]+/ {
        sub(/^[#[:space:]]*/, "", $1);
        print $1
    }' "$LOCALE_GEN" | sort -u
)

[[ ${#AVAILABLE_LOCALES[@]} -gt 0 ]] || { error_msg "No UTF-8 locales found in $LOCALE_GEN."; exit 1; }

# TODO: Add a default locale in case the user cancels the selection or selects nothing
# TODO: For now, we will default to en_US.UTF-8 if available
# Prompt user to select locales to generate
SELECTED_LOCALES=()
if SELECTION=$(printf '%s\n' "${AVAILABLE_LOCALES[@]}" |
    gum filter --no-limit --height 10 --header="Select locales to generate (Tab to toggle, Enter to confirm)"); then
    mapfile -t SELECTED_LOCALES <<<"$SELECTION"
fi

# Fallback if user cancels or selects nothing
if [[ ${#SELECTED_LOCALES[@]} -eq 0 ]]; then
    status_msg "No locales selected. Defaulting to '$DEFAULT_LOCALE' only"
    SELECTED_LOCALES=("$DEFAULT_LOCALE")
fi

debug_msg "Selected locales: ${SELECTED_LOCALES[*]}"

# Choose default LANG from the selected locales
DEFAULT_CHOICE=$(printf '%s\n' "${SELECTED_LOCALES[@]}" |
    gum filter --height 10 --header="Select default locale (LANG) for the system")

DEFAULT_CHOICE=${DEFAULT_CHOICE:-$DEFAULT_LOCALE}
debug_msg "Default locale chosen: $DEFAULT_CHOICE"

# Re-comment all UTF-8 locales, then uncomment only the selected ones
status_msg "Updating $LOCALE_GEN for selected locales..."

sed -i -E 's/^([[:space:]]*)([A-Za-z0-9_\.@-]+[[:space:]]+[A-Za-z0-9_\.-]+)/#\1\2/' "$LOCALE_GEN"

for loc in "${SELECTED_LOCALES[@]}"; do
    sed -i -E "s/^[#[:space:]]*(${loc}[[:space:]]+[A-Za-z0-9_\.-]+.*)/\1/" "$LOCALE_GEN"
done

# Generate locales inside the target system
status_msg "Generating selected locales..."
chroot_exec locale-gen

# Create /etc/locale.conf with the chosen default LANG
cat >"$TARGET_MNT/etc/locale.conf" <<EOF
LANG=$DEFAULT_CHOICE
EOF

# Write keyboard layout to /etc/vconsole.conf for virtual console
cat >"$TARGET_MNT/etc/vconsole.conf" <<EOF
KEYMAP=$KEYBOARD_LAYOUT
EOF

success_msg "Locales generated: ${SELECTED_LOCALES[*]}"
success_msg "Default system locale (LANG) set to: $DEFAULT_CHOICE"
success_msg "Keyboard layout '$KEYBOARD_LAYOUT' written to vconsole.conf"
