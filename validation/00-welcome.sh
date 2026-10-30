#!/bin/bash

# validation/00-welcome — UEFI/root + RAM preconditions.
#   pre : host preconditions mentioned in the title
#   post: no postconditions to assert

VALIDATE_APIS=(validation.core.check core.ui)

validate::00_welcome() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            if check::is_dryrun; then
                debug_msg "validation 00 pre: dry-run; host assertions skipped"
                return 0
            fi
            if ! check::is_uefi; then
                check::fail "efivars missing — this installer supports UEFI boot only"
                return 1
            fi
            if ! check::is_root; then
                check::fail "installer must run as root"
                return 1
            fi

            local ram_kib ram_gb
            ram_kib=$(awk '/MemTotal/{print $2}' /proc/meminfo)
            ram_gb=$((ram_kib / 1048576))
            debug_msg "validation 00: RAM ${ram_kib}KB (${ram_gb}GB)"

            if ((ram_gb < 1)); then
                warn_msg "Less than 1GB RAM; installation may fail"
                if ! ui::confirm low_ram_continue "Continue anyway?" "no"; then
                    check::fail "aborted at the low-RAM prompt"
                    return 1
                fi
                warn_msg "Proceeding with less than 1GB RAM"
            elif ((ram_gb < 2)); then
                status_msg "Less than 2GB RAM; installation may be slow"
            fi
            return 0
            ;;
        post)
            return 0
            ;;
        *)
            error_msg "validation 00: unknown mode '$mode'"
            return 2
            ;;
    esac
}

return 0
