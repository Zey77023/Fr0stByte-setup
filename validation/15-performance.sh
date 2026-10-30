#!/bin/bash

# validation/15-performance —
# pre: no need to check any conditions
# post: every state perf/<tweak> key must have its deployed artifact with the tweak
# content, and trim must show fstrim.timer's schedule symlink. The
# flags file (performance.conf) carries exactly one PROFILE_* row per
# accepted toggle with no orphan rows. Declined toggles must have
# neither artifact nor flag row; the reset script is present unconditionally and
# executable.

VALIDATE_APIS=(validation.core.check core.state config.performance)

# __v15_require <content> <file> — check tweak content inside a
# deployed asset.
__v15_require() {
    grep -Fq "$1" "$2" || {
        check::fail "tweak artifact incomplete or absent: $2"
        return 1
    }
}

validate::15_performance() {
    local mode="$1" mnt="${2:-}"

    case "$mode" in
        pre)
            debug_msg "validation 15 pre: nothing to gate (optional stage)"
            ;;
        post)
            if check::is_dryrun; then
                debug_msg "validation 15 post: dry-run; file assertions skipped"
                return 0
            fi
            local flags="$mnt/etc/fr0stbyte/performance.conf"

            local -a __v15_tweaks=()
            mapfile -t __v15_tweaks < <(performance::tweaks)

            local t flag rel
            local __v15_accepted=0
            for t in "${__v15_tweaks[@]}"; do
                flag="$(performance::flag_of "$t")" || return 1
                rel="$(performance::asset_of "$t" || true)"
                if state_has "perf/$t"; then
                    (( __v15_accepted += 1 ))
                    __v15_require "$flag=\"enabled\"" "$flags" || return 1
                    case "$t" in
                        swappiness)
                            __v15_require 'vm.swappiness = 100' \
                                "$mnt/$rel" || return 1 ;;
                        page_cluster)
                            __v15_require 'vm.page-cluster = 0' \
                                "$mnt/$rel" || return 1 ;;
                        bbr)
                            __v15_require 'net.core.default_qdisc = fq' \
                                "$mnt/$rel" \
                            && __v15_require \
                                'net.ipv4.tcp_congestion_control = bbr' \
                                "$mnt/$rel" \
                                || return 1 ;;
                        trim)
                            [[ -L "$mnt/etc/systemd/system/timers.target.wants/fstrim.timer" ]] \
                                || {
                                    check::fail "fstrim.timer not scheduled in the target"
                                    return 1
                                } ;;
                        low_latency_audio)
                            __v15_require 'default.clock.quantum = 256' \
                                "$mnt/$rel" || return 1 ;;
                        journald_limits)
                            __v15_require 'SystemMaxUse=500M' \
                                "$mnt/$rel" || return 1 ;;
                    esac
                else
                    if [[ -f "$flags" ]] && grep -Fq "$flag=" "$flags"; then
                        check::fail "declined tweak '$t' has a flag row in $flags"
                        return 1
                    fi
                    if [[ -n "$rel" && -e "$mnt/$rel" ]]; then
                        check::fail "declined tweak '$t' left a stale artifact: $mnt/$rel"
                        return 1
                    fi
                fi
            done

            local n_rows=0
            [[ -f "$flags" ]] && n_rows="$(grep -c '^PROFILE_' "$flags" || true)"
            (( n_rows == __v15_accepted )) || {
                check::fail "flags file rows ($n_rows) != accepted toggles ($__v15_accepted): $flags"
                return 1
            }

            local reset="$mnt/usr/local/sbin/fr0stbyte-performance-reset"
            [[ -x "$reset" ]] || {
                check::fail "performance reset script missing or not executable: $reset"
                return 1
            }
            ;;
        *)
            error_msg "validation 15: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
