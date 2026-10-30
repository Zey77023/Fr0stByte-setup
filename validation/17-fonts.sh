#!/bin/bash

# validation/17-fonts
# pre: aur/chaotic present
# post: if fonts/installed is present, check fontconfig deployment

VALIDATE_APIS=(validation.core.check core.state)

validate::17_fonts() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            check::require_state "aur/chaotic" "17-fonts" || return 1
            ;;
        post)
            if ! state_has "fonts/installed"; then
                debug_msg "validation 17 post: fonts were declined; nothing to assert"
                return 0
            fi
            if check::is_dryrun; then
                debug_msg "validation 17 post: dry-run; file assertions skipped"
                return 0
            fi
            local conf="$mnt/etc/fonts/local.conf"
            check::require_file "$conf" || return 1
            local -a rows=(
                '<family>Noto Sans</family>'
                '<family>Roboto</family>'
                '<family>DejaVu Sans</family>'
                '<family>Liberation Sans</family>'
                '<family>Liberation Serif</family>'
                '<family>Liberation Mono</family>'
            )
            local row
            for row in "${rows[@]}"; do
                grep -Fq "$row" "$conf" || {
                    check::fail "fontconfig preferences incomplete: missing $row"
                    return 1
                }
            done
            ;;
        *)
            error_msg "validation 17: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
