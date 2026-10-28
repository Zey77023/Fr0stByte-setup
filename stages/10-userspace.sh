#!/bin/bash

# stage 10 — userspace: hostname + username prompts,
# passwords  for root and the userm sudoers deployment,
# XDG user directories for the created user

STAGE_ID="10-userspace"
STAGE_KIND="interactive"
STAGE_DESC="Hostname, root + user passwords, user creation, sudoers, XDG dirs"
STAGE_APIS=(core.state core.secret config.users config.files_apply system.chroot)

run_stage() {
    debug_msg "Starting userspace configuration stage"
    status_msg "Userspace configuration..."

    local st_input st_hostname=""
    local st_default_hostname="frostbyte"
    while :; do
        if ! st_input=$(ui::input \
            --placeholder "Enter hostname (e.g. frostbyte)" \
            --value "$st_default_hostname"); then
            error_msg "Hostname prompt cancelled"
            return 1
        fi
        if [[ -z "$st_input" ]]; then
            error_msg "Hostname cannot be empty"
            continue
        fi
        st_hostname=$(printf '%s' "$st_input" | tr '[:upper:]' '[:lower:]')
        users::hostname_validate "$st_hostname" && break
    done
    users::hostname_set "$TARGET_MNT" "$st_hostname" || return 1
    users::hosts_file "$TARGET_MNT" "$st_hostname" || return 1
    state_set "hosts/hostname" "$st_hostname"
    success_msg "Hostname set to '$st_hostname'"

    secret::scope "root" -- users::password_set "$TARGET_MNT" root || return 1
    success_msg "Root password set"

    local st_user=""
    while :; do
        if ! st_input=$(ui::input \
            --placeholder "Enter username (non-root)" \
            --value "user"); then
            error_msg "Username prompt cancelled"
            return 1
        fi
        if [[ -z "$st_input" ]]; then
            error_msg "Username cannot be empty"
            continue
        fi
        if [[ "$st_input" == "root" ]]; then
            error_msg "Username 'root' is reserved"
            continue
        fi
        if [[ ! "$st_input" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            error_msg "Invalid username. Use lowercase letters, digits, '_' or '-', starting with a letter or '_'"
            continue
        fi
        if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
            debug_msg "DRY-RUN: target user-existence check skipped ($st_input assumed free)"
            st_user="$st_input"
            break
        fi
        local st_rc=""
        chroot_exec "$TARGET_MNT" --expect "0 1" --code st_rc -- id -u "$st_input" \
            2>/dev/null || true
        if [[ "$st_rc" != "1" ]]; then
            error_msg "User '$st_input' already exists in target system"
            continue
        fi
        st_user="$st_input"
        break
    done
    debug_msg "Username set to: $st_user"

    us_create_user() {
        users::users_add "$TARGET_MNT" "$st_user" "wheel" || return 1
        users::password_set "$TARGET_MNT" "$st_user" "$1"
    }

    secret::scope "$st_user" -- us_create_user || return 1
    state_set "users/user" "$st_user"
    success_msg "User '$st_user' created"

    files_apply::apply "$TARGET_MNT" --only "etc/sudoers.d/99_wheel" || return 1
    success_msg "Sudo configured"

    status_msg "Creating XDG user directories..."
    users::xdg_dirs "$TARGET_MNT" "$st_user" || return 1
    success_msg "XDG user directories configured for '$st_user'"
    return 0
}
