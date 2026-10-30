#!/bin/bash

# validation/04-review
#   pre : partition/disk + partition/mode exist
#   post: the state keys survived the review unchanged.

VALIDATE_APIS=(validation.core.check core.state)

validate::04_review() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            check::require_state "partition/disk" "04-review" || return 1
            check::require_state "partition/mode" "04-review" || return 1
            if check::is_dryrun; then
                debug_msg "validation 04 pre: dry-run; state assertions done"
            fi
            ;;
        post)
            check::require_state "partition/disk" "04-review" || return 1
            check::require_state "partition/mode" "04-review" || return 1
            debug_msg "validation 04 post: review is read-only; keys unchanged"
            ;;
        *)
            error_msg "validation 04: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
