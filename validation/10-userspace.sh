#!/bin/bash

# validation/10-userspace
# pre : proof of successful pacstrap
# post: hosts/hostname + users/user landed and /etc/hostname, the sudoers asset
# is deployed with mode 0440, the user's XDG config exists, and visudo
# accepts the sudoers set when the target ships visudo.

VALIDATE_APIS=(validation.core.check core.state system.chroot)

validate::10_userspace() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            if check::is_dryrun; then
                debug_msg "validation 10 pre: dry-run; container check skipped"
                return 0
            fi
            check::require_file "$mnt/etc/passwd" || return 1
            ;;
        post)
            check::require_state "hosts/hostname" "10-userspace" || return 1
            check::require_state "users/user" "10-userspace" || return 1
            if check::is_dryrun; then
                debug_msg "validation 10 post: dry-run; file assertions skipped"
                return 0
            fi
            local user hostname
            user="$(state_get users/user)"
            hostname="$(state_get hosts/hostname)"
            if ! [[ -f "$mnt/etc/hostname" ]] \
                || ! grep -Fxq "$hostname" "$mnt/etc/hostname"; then
                check::fail "/etc/hostname does not contain: $hostname"
                return 1
            fi
            check::require_file "$mnt/etc/sudoers.d/99_wheel" || return 1
            if [[ "$(stat -c '%a' "$mnt/etc/sudoers.d/99_wheel")" != "440" ]]; then
                check::fail "sudoers asset is not mode 0440: $mnt/etc/sudoers.d/99_wheel"
                return 1
            fi
            check::require_file "$mnt/home/$user/.config/user-dirs.dirs" || return 1
            # read-only visudo probe (zero mutations); skipped when the
            # probe does not cleanly succeed (no visudo, no chroot)
            if chroot_exec "$mnt" --expect "0" -- bash -c 'command -v visudo' \
                >/dev/null 2>&1; then
                if ! chroot_exec "$mnt" -- visudo -cf /etc/sudoers >/dev/null 2>&1; then
                    check::fail "invalid /etc/sudoers in target"
                    return 1
                fi
                if ! chroot_exec "$mnt" -- visudo -cf /etc/sudoers.d/99_wheel \
                    >/dev/null 2>&1; then
                    check::fail "invalid sudoers asset in target"
                    return 1
                fi
            else
                debug_msg "validation 10 post: no visudo in target; sudoers syntax unchecked"
            fi
            ;;
        *)
            error_msg "validation 10: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
