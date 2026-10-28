#!/bin/bash

# stage 15 — performance: optional opt-in tweaks. Not necessarrily related to performance
# but many essential to everyday system use and security.

STAGE_ID="15-performance"
STAGE_KIND="mutating"
STAGE_DESC="Optional opt-in performance tweaks (swappiness, page-cluster, BBR, TRIM, PipeWire, journald)"
STAGE_APIS=(
    core.state core.ui
    config.performance config.files_apply
    system.chroot
)

run_stage() {
    debug_msg "Starting optional performance profile stage"
    status_msg "Optional performance tweaks"

    performance::cleanup "$TARGET_MNT" || return 1

    local -a st_tweaks=()
    mapfile -t st_tweaks < <(performance::tweaks)
    local st_tweak st_key st_prompt
    for st_tweak in "${st_tweaks[@]}"; do
        if [[ "$st_tweak" == "bbr" ]] && ! performance::bbr_available; then
            status_msg "BBR is unavailable in the running kernel; skipping that tweak"
            continue
        fi

        case "$st_tweak" in
            swappiness)        st_prompt="Set vm.swappiness=100 for zram?" ;;
            page_cluster)      st_prompt="Set vm.page-cluster=0 for zram?" ;;
            bbr)               st_prompt="Enable the BBR network congestion-control tweak?" ;;
            trim)              st_prompt="Enable SSD TRIM (discard) support?" ;;
            low_latency_audio) st_prompt="Enable low-latency sound tweaks for PipeWire?" ;;
            journald_limits)   st_prompt="Enable journaling limits for systemd-journald?" ;;
        esac

        st_key="perf_$st_tweak"
        if ui::confirm "$st_key" "$st_prompt" "no"; then
            performance::apply "$TARGET_MNT" "$st_tweak" || return 1
            performance::flag_write "$TARGET_MNT" "$st_tweak" || return 1
            state_set "perf/$st_tweak" "enabled"
            success_msg "Enabled the $st_tweak tweak"
        else
            status_msg "${st_tweak} tweak declined"
            if state_has "perf/$st_tweak"; then
                state_unset "perf/$st_tweak"
            fi
        fi
    done

    files_apply::apply "$TARGET_MNT" \
        --only usr/local/sbin/fr0stbyte-performance-reset || return 1

    status_msg "Performance tweaks complete"
    return 0
}
