#!/bin/bash

# validation/06-pacstrap
# pre: network reachable, pacstrap-packages present
# post: no postconditions to assert since pacstrap will exit with error
# if anything goes sideways during installation

VALIDATE_APIS=(validation.core.check core.checks pkg.pacman)

validate::06_pacstrap() {
    local mode="$1" mnt="${2:-}"
    local list_file

    case "$mode" in
        pre)
            if ! check::is_dryrun; then
                require_network || return 1
            fi
            if [[ -n "${FR0ST_PACSTRAP_PKGS:-}" ]]; then
                list_file="$FR0ST_PACSTRAP_PKGS"
            elif [[ -n "${INSTALLER_ROOT:-}" ]]; then
                list_file="$INSTALLER_ROOT/lib/pkg/lists/pacstrap-packages"
            else
                check::fail "package list path not anchored " \
                    "(FR0ST_PACSTRAP_PKGS / INSTALLER_ROOT missing)"
                return 1
            fi
            check::require_file "$list_file" || return 1

            # ! linux-zen is required because linux header detection
            # ! hardcodes linux-zen-headers in the stage
            if ! tr -d '\r' <"$list_file" | grep -qx 'linux-zen'; then
                check::fail "linux-zen is required; " \
                    "kernel selection is not configurable in this installer"
                return 1
            fi
            ;;
        post)
            return 0
            ;;
        *)
            error_msg "validation 06: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
