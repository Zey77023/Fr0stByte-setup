#!/bin/bash

debug_msg "Starting userspace configuration stage"

status_msg "Userspace configuration..."

# Hostname
DEFAULT_HOSTNAME="frostbyte"

while true; do
    HOSTNAME_INPUT=$(gum input \
        --placeholder "Enter hostname (e.g. frostbyte)" \
        --value "$DEFAULT_HOSTNAME")

    [[ -n "$HOSTNAME_INPUT" ]] || { error_msg "Hostname cannot be empty"; continue; }

    HOSTNAME_LOWER=$(echo "$HOSTNAME_INPUT" | tr 'A-Z' 'a-z')

    # RFC 1123 validation
    if [[ ${#HOSTNAME_LOWER} -gt 253 ]]; then
        error_msg "Hostname too long (max 253 characters)"
        continue
    fi

    if [[ ! "$HOSTNAME_LOWER" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]]; then
        error_msg "Invalid hostname. Use letters, digits, and '-', no leading/trailing '-'"
        continue
    fi

    HOSTNAME="$HOSTNAME_LOWER"
    break
done

echo "$HOSTNAME" >"$TARGET_MNT/etc/hostname"

# Minimal /etc/hosts
if [[ ! -f "$TARGET_MNT/etc/hosts" ]]; then
    cat >"$TARGET_MNT/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF
fi

success_msg "Hostname set to '$HOSTNAME'"

# Root password
ROOT_PASS=$(request_password "root") || exit 1
echo "root:$ROOT_PASS" | chroot_exec chpasswd
success_msg "Root password set"

unset ROOT_PASS

# User creation
DEFAULT_USER="user"

while true; do
    NEW_USER=$(gum input \
        --placeholder "Enter username (non-root)" \
        --value "$DEFAULT_USER")

    [[ -n "$NEW_USER" ]] || { error_msg "Username cannot be empty"; continue; }
    [[ "$NEW_USER" == "root" ]] && { error_msg "Username 'root' is reserved"; continue; }

    if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        error_msg "Invalid username. Use lowercase letters, digits, '_' or '-', starting with a letter or '_'"
        continue
    fi

    # Check if user exists - expect exit 0 (exists) or 1 (doesn't exist)
    chroot_exec --expect "0 1" id -u "$NEW_USER" &>/dev/null
    if [[ $CHROOT_EXEC_EXIT_CODE -eq 0 ]]; then
        error_msg "User '$NEW_USER' already exists in target system"
        continue
    fi

    break
done

debug_msg "Username set to: $NEW_USER"
USER_PASS=$(request_password "$NEW_USER") || exit 1

chroot_exec useradd -mG wheel "$NEW_USER"
echo "$NEW_USER:$USER_PASS" | chroot_exec chpasswd
success_msg "User '$NEW_USER' created"

unset USER_PASS

# Sudo configuration
SUDOERS_D="$TARGET_MNT/etc/sudoers.d"
mkdir -p "$SUDOERS_D"

cat >"$SUDOERS_D/99_wheel" <<'EOF'
Defaults rootpw
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 "$SUDOERS_D/99_wheel"

if chroot_exec bash -c "command -v visudo" &>/dev/null; then
    chroot_exec visudo -cf /etc/sudoers.d/99_wheel || { error_msg "visudo validation failed"; exit 1; }
fi

success_msg "Sudo configured"

# XDG user directories belong to the created user's environment, not root's.
status_msg "Creating XDG user directories..."
chroot_exec runuser -u "$NEW_USER" -- xdg-user-dirs-update
[[ -s "$TARGET_MNT/home/$NEW_USER/.config/user-dirs.dirs" ]] || {
    error_msg "XDG user directories were not created for $NEW_USER"
    exit 1
}
chroot_exec stat -c '%U %a' "/home/$NEW_USER/.config/user-dirs.dirs"
success_msg "XDG user directories configured for '$NEW_USER'"

# Validate the complete sudoers include set, not only the file we generated.
chroot_exec visudo -cf /etc/sudoers
USER_GROUPS=$(chroot_exec id -nG "$NEW_USER")
[[ " $USER_GROUPS " == *" wheel "* ]] || {
    error_msg "User '$NEW_USER' is not a member of wheel"
    exit 1
}
USER_HOME_MODE=$(chroot_exec stat -c '%a' "/home/$NEW_USER")
[[ "$USER_HOME_MODE" =~ ^[0-7]{3,4}$ ]] || {
    error_msg "Could not validate permissions on /home/$NEW_USER"
    exit 1
}
success_msg "User, home directory, wheel membership, and sudoers validated"
success_msg "Userspace setup complete"
