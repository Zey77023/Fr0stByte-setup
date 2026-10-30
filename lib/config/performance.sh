#!/bin/bash

# performance profile

if [[ ${_SOURCED_config_performance:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_performance="loaded"

module::provide config.performance performance::cleanup \
    performance::bbr_available performance::asset_of \
    performance::apply performance::flag_write \
    performance::tweaks performance::flag_of

# performance::tweaks — canonical opt-in toggle list
performance::tweaks() {
    printf '%s\n' swappiness page_cluster bbr trim low_latency_audio journald_limits
}

# performance::cleanup <mnt> - remove every
# tweak file plus the flags file before re-applying, so declined
# toggles cannot leave opt-in files.
performance::cleanup() {
    local mnt="$1" t rel
    local -a targets=("$mnt/etc/fr0stbyte/performance.conf")
    while IFS= read -r t; do
        rel="$(performance::asset_of "$t")" || return 1
        if [[ -n "$rel" ]]; then
            targets+=("$mnt/$rel")
        fi
    done < <(performance::tweaks)
    exec_cmd rm -f "${targets[@]}"
}

# performance::bbr_available — does the running kernel list bbr?
performance::bbr_available() {
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: BBR availability assumed (canonical: available)"
        return 0
    fi
    local avail
    avail="$(cat "${FR0ST_BBR_PROBE:-/proc/sys/net/ipv4/tcp_allowed_congestion_control}" \
        2>/dev/null || true)"
    [[ " $avail " == *" bbr "* ]]
}

# performance::asset_of <tweak> — get file relpath for a toggle.
performance::asset_of() {
    case "$1" in
        swappiness)        printf '%s\n' etc/sysctl.d/60-fr0stbyte-swappiness.conf ;;
        page_cluster)      printf '%s\n' etc/sysctl.d/61-fr0stbyte-page-cluster.conf ;;
        bbr)               printf '%s\n' etc/sysctl.d/62-fr0stbyte-bbr.conf ;;
        trim)              return 0 ;;
        low_latency_audio) printf '%s\n' \
                               etc/pipewire/pipewire.conf.d/00-fr0stbyte-performance.conf ;;
        journald_limits)   printf '%s\n' \
                               etc/systemd/journald.conf.d/00-fr0stbyte-performance.conf ;;
        *) error_msg "performance: unknown tweak '$1'"; return 1 ;;
    esac
}

# performance::apply <mnt> <tweak> — deploy the toggle's file into the target
performance::apply() {
    local mnt="$1" tweak="$2" rel
    rel="$(performance::asset_of "$tweak")" || return 1
    if [[ -n "$rel" ]]; then
        files_apply::apply "$mnt" --only "$rel" || return 1
    fi
    if [[ "$tweak" == "trim" ]]; then
        chroot_exec "$mnt" -- systemctl enable fstrim.timer || return 1
    fi
    return 0
}

# performance::flag_of <tweak> — get PROFILE_* flag name in the flags file.
performance::flag_of() {
    case "$1" in
        swappiness)        printf '%s\n' PROFILE_SWAPPINESS ;;
        page_cluster)      printf '%s\n' PROFILE_PAGE_CLUSTER ;;
        bbr)               printf '%s\n' PROFILE_NETWORK_BBR ;;
        trim)              printf '%s\n' PROFILE_SSD_TRIM ;;
        low_latency_audio) printf '%s\n' PROFILE_LOW_LATENCY_SOUND ;;
        journald_limits)   printf '%s\n' PROFILE_JOURNALD_LIMITS ;;
        *) error_msg "performance: unknown tweak '$1'"; return 1 ;;
    esac
}

# performance::flag_write <mnt> <tweak> — append PROFILE_* flag line in the flags file.
performance::flag_write() {
    local mnt="$1" tweak="$2" flag
    flag="$(performance::flag_of "$tweak")" || return 1
    exec_cmd mkdir -p "$mnt/etc/fr0stbyte" || return 1
    exec_cmd sh -c \
        "printf '%s\n' '$flag=\"enabled\"' >> '$mnt/etc/fr0stbyte/performance.conf'"
}

return 0
