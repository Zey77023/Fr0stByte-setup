#!/bin/bash
# validation/12-pacman
# pre: the target has pacman.conf
# post: state aur/chaotic, conf has multilib enabled
# + [chaotic-aur] + the eye-candy options, and the chaotic mirrorlist
# with the keyring package

VALIDATE_APIS=(validation.core.check core.state)

validate::12_pacman() {
    local mode="$1" mnt="${2:-}"
    local conf="$mnt/etc/pacman.conf"

    case "$mode" in
        pre)
            if check::is_dryrun; then
                debug_msg "validation 12 pre: dry-run; conf check skipped"
                return 0
            fi
            check::require_file "$conf" || return 1
            ;;
        post)
            check::require_state "aur/chaotic" "12-pacman" || return 1
            if check::is_dryrun; then
                debug_msg "validation 12 post: dry-run; conf assertions skipped"
                return 0
            fi
            if ! grep -q '^\[multilib\]' "$conf"; then
                check::fail "multilib section not enabled: $conf"
                return 1
            fi
            if ! grep -q '^\[chaotic-aur\]' "$conf"; then
                check::fail "chaotic-aur section missing: $conf"
                return 1
            fi
            if ! grep -q '^Include = /etc/pacman.d/chaotic-mirrorlist' "$conf"; then
                check::fail "chaotic-aur Include line missing: $conf"
                return 1
            fi
            if ! grep -q '^ILoveCandy$' "$conf"; then
                check::fail "ILoveCandy missing from [options]: $conf"
                return 1
            fi
            if ! grep -q '^VerbosePkgLists$' "$conf"; then
                check::fail "VerbosePkgLists missing from [options]: $conf"
                return 1
            fi
            check::require_file "$mnt/etc/pacman.d/chaotic-mirrorlist" || return 1
            ;;
        *)
            error_msg "validation 12: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
