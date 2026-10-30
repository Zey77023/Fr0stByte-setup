#!/bin/bash

# validation/14-services
# pre: require keys for luks/name and swap/file and verify fstab existence
# post: require keys services/done, fstab rows for swap configuration, zram-generator.conf,
# the hybrid-sleep drop-in, services/ssh_user when configured, /var/tmp existence checking for
# NVIDIA VRAM dumps

VALIDATE_APIS=(validation.core.check core.state system.fstab system.detect)

validate::14_services() {
    local mode="$1" mnt="${2:-}"
    local fstab="$mnt/etc/fstab"

    case "$mode" in
        pre)
            check::require_state "luks/name" "14-services" || return 1
            check::require_state "swap/file" "14-services" || return 1
            if check::is_dryrun; then
                debug_msg "validation 14 pre: dry-run; fstab check skipped"
                return 0
            fi
            check::require_file "$fstab" || return 1
            ;;
        post)
            check::require_state "services/done" "14-services" || return 1
            if check::is_dryrun; then
                debug_msg "validation 14 post: dry-run; file assertions skipped"
                return 0
            fi
            # D-6: exactly one @swap subvol row and one swapfile row,
            # with the hibernation device at priority -1
            if ! (( "$(fstab_entry_count "$fstab" \
                "/dev/mapper/$(state_get luks/name "")" "/swap" "btrfs")" == 1 )); then
                check::fail "swap subvolume entry missing or duplicated: $fstab"
                return 1
            fi
            if ! (( "$(fstab_entry_count "$fstab" \
                "$(state_get swap/file "")" "none" "swap")" == 1 )); then
                check::fail "swapfile entry missing or duplicated: $fstab"
                return 1
            fi
            if ! grep -Fq 'defaults,pri=-1' "$fstab"; then
                check::fail "swapfile row lacks the D-6 priority -1: $fstab"
                return 1
            fi
            # zram-generator wiring
            local zconf="$mnt/etc/systemd/zram-generator.conf"
            if ! grep -Fq 'swap-priority = 100' "$zconf" \
                || ! grep -Fq 'compression-algorithm = ' "$zconf"; then
                check::fail "zram-generator.conf incomplete: $zconf"
                return 1
            fi
            # hybrid-sleep drop-in with the profile knob applied
            local hconf="$mnt/etc/systemd/sleep.conf.d/10-fr0stbyte-hibernate.conf"
            if ! grep -Fq 'AllowSuspendThenHibernate=yes' "$hconf" \
                || ! grep -Eq '^HibernateDelaySec=[[:alnum:]]+$' "$hconf"; then
                check::fail "hybrid-sleep drop-in incomplete: $hconf"
                return 1
            fi
            # per-user SSH drop-in when the user opted in
            local ssh_dropin="$mnt/etc/ssh/sshd_config.d/10-fr0stbyte-key-only.conf"
            if state_has "services/ssh_user"; then
                if ! grep -Fq "AllowUsers $(state_get services/ssh_user "")" "$ssh_dropin" \
                    || ! grep -Fq 'PasswordAuthentication no' "$ssh_dropin"; then
                    check::fail "key-only sshd drop-in incomplete: $ssh_dropin"
                    return 1
                fi
            fi

            local -a st_gpu_pkgs=()
            if ! check::is_dryrun && detect::gpu_pkgs st_gpu_pkgs \
                && (( ${#st_gpu_pkgs[@]} > 0 )); then
                if [[ ! -d "$mnt/var/tmp" ]]; then
                    check::fail "NVIDIA target lacks the /var/tmp VRAM workspace"
                    return 1
                fi
                if (( $(df -Pm "$mnt/var/tmp" | awk 'NR==2 {print $4}') < 2048 )); then
                    warn_msg "validation 14: <2 GiB free under $mnt/var/tmp — NVIDIA VRAM suspend dumps may not fit"
                fi
            fi
            ;;
        *)
            error_msg "validation 14: unknown mode '$mode'"
            return 2
            ;;
    esac
    return 0
}

return 0
