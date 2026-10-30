#!/bin/bash

# validation/01-bootstrap — pre: dependency list exists + network reachable
# post: no postconditions to assert

VALIDATE_APIS=(validation.core.check core.checks)

validate::01_bootstrap() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            local deps_file="${FR0ST_SCRIPT_DEPS:-$INSTALLER_ROOT/lib/pkg/lists/script-dependencies}"
            if ! check::require_file "$deps_file"; then
                return 1
            fi
            if [[ ${FR0ST_DRYRUN:-0} != "1" ]]; then
                if ! require_network; then
                    check::fail "network connectivity required for bootstrap"
                    return 1
                fi
            fi
            return 0
            ;;
        post)
            return 0
            ;;
        *)
            error_msg "validation 01: unknown mode '$mode'"
            return 2
            ;;
    esac
}

return 0
