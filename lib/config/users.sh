#!/bin/bash

# Userspace APIs: hostname, /etc/hosts, user creation, password
# application, XDG dirs and sudoers file configuration.

if [[ ${_SOURCED_config_users:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_users="loaded"

module::provide config.users users::hostname_validate users::hostname_set \
    users::hosts_file users::users_add users::password_set users::xdg_dirs

# users::hostname_validate <candidate> — RFC 1123.
users::hostname_validate() {
    local name="$1"
    (( ${#name} <= 253 )) || {
        error_msg "Hostname too long (max 253 characters)"
        return 1
    }
    [[ "$name" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]] || {
        error_msg "Invalid hostname. Use letters, digits, and '-', no leading/trailing '-'"
        return 1
    }
    return 0
}

# users::hostname_set <mnt> <hostname>
users::hostname_set() {
    local mnt="$1" hostname="$2"
    exec_cmd tee "$mnt/etc/hostname" >/dev/null <<EOS
$hostname
EOS
    return 0
}

# users::hosts_file <mnt> <hostname> — minimal hosts, only when absent.
# Dry-run mirror (§8.2): an un-pacstrapped container has no /etc/hosts,
# so the "only when absent" read cannot hold; the tee journals and
# no-ops, keep the canonical write in the journal anyway.
users::hosts_file() {
    local mnt="$1" hostname="$2"
    if [[ ! -f "$mnt/etc/hosts" && ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: no target /etc/hosts; hosts write journaled"
    elif [[ -f "$mnt/etc/hosts" ]]; then
        return 0
    fi
    exec_cmd tee "$mnt/etc/hosts" >/dev/null <<EOS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOS
    return 0
}

# users::users_add <mnt> <user> [groups…]
#   Creates the user with -m and the extra groups.
users::users_add() {
    local mnt="$1" user="$2"
    shift 2
    local -a groups=()
    [[ $# -gt 0 ]] && groups=("$@")
    local -a args=(-m)
    local g
    for g in "${groups[@]}"; do
        args+=(-G "$g")
    done
    chroot_exec "$mnt" -- useradd "${args[@]}" "$user" || return 1
    return 0
}

# users::password_set <mnt> <user> <passfile>
users::password_set() {
    local mnt="$1" user="$2" passfile="$3"
    [[ -s "$passfile" ]] || {
        error_msg "Password passfile is empty: $passfile"
        return 1
    }
    {
        printf '%s:' "$user"
        cat "$passfile"
    } | chroot_exec "$mnt" -- chpasswd
    return 0
}

# users::xdg_dirs <mnt> <user> — xdg-user-dirs-update for that user.
users::xdg_dirs() {
    local mnt="$1" user="$2"

    chroot_exec "$mnt" -- runuser -u "$user" -- xdg-user-dirs-update || return 1
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: assuming user-dirs.dirs created for $user"
        return 0
    fi
    [[ -s "$mnt/home/$user/.config/user-dirs.dirs" ]] || {
        error_msg "XDG user directories were not created for $user"
        return 1
    }
    chroot_exec "$mnt" -- stat -c '%U %a' "/home/$user/.config/user-dirs.dirs" || return 1
    return 0
}

return 0
