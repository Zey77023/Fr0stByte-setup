#!/bin/bash

# stage 14 — services: NM + UFW, zram, optional diagnostics packages, swap fstab entries,
# NVIDIA sleep/hibernate handling, optional SSH.

STAGE_ID="14-services"
STAGE_KIND="interactive"
STAGE_DESC="Enable NetworkManager/UFW, zram, diag tools, hibernation, swap fstab, NVIDIA sleep/hibernate and optional SSH"
STAGE_APIS=(
    core.state core.ui config.services config.initramfs
    pkg.lists pkg.pacman system.fstab system.detect system.chroot
)

run_stage() {
    debug_msg "Starting services configuration stage"
    status_msg "Enabling essential system services..."

    services::svc_enable "$TARGET_MNT" NetworkManager || return 1
    if services::svc_disable "$TARGET_MNT" dhcpcd.service; then
        status_msg "Disabled competing dhcpcd service"
    fi
    success_msg "NetworkManager enabled"

    status_msg "Configuring UFW firewall policy..."
    services::ufw_policy "$TARGET_MNT" || return 1
    success_msg "UFW enabled with deny-incoming and allow-outgoing defaults"

    status_msg "Configuring zram..."
    local st_zram_size="${ZRAM_SIZE:-ram/2}" st_zram_comp="${ZRAM_COMPRESSION:-zstd}"
    services::zram_conf "$TARGET_MNT" "$st_zram_size" "$st_zram_comp" || return 1
    success_msg "Zram-generator configured at $TARGET_MNT/etc/systemd/zram-generator.conf ($st_zram_size, $st_zram_comp)"

    if ui::confirm diagnostics_install \
        "Install optional hardware and performance diagnostic tools?" "no"; then
        local st_diag_list="${FR0ST_DIAG_PKGS:-$INSTALLER_ROOT/lib/pkg/lists/optional-diagnostic-packages}"
        local -a st_diag_pkgs=()
        lists::load "$st_diag_list" st_diag_pkgs || return 1
        pacman::target "$TARGET_MNT" -S --needed --noconfirm "${st_diag_pkgs[@]}" || return 1
        success_msg "Optional diagnostic tools installed"
    else
        status_msg "Optional diagnostic tools not installed"
    fi

    status_msg "Configuring swap file for hibernation..."
    local st_mapper st_swapsrc
    st_swapsrc="$(state_get swap/file "/swap/swapfile")"
    st_mapper="/dev/mapper/$(state_get luks/name "cryptroot")"
    ensure_fstab_entry "$TARGET_MNT/etc/fstab" "$st_mapper" "/swap" "btrfs" \
        "subvol=@swap,nodatacow,discard=async" "0" "0" || return 1
    fstab::swapfile_entry "$TARGET_MNT/etc/fstab" "$st_swapsrc" "none" || return 1
    chroot_exec "$TARGET_MNT" -- findmnt --verify --tab-file /etc/fstab || return 1
    success_msg "Swap subvolume and swapfile entries are configured in fstab"

    local -a st_gpu_pkgs=()
    if [[ ${FR0ST_DRYRUN:-0} != "1" ]]; then
        status_msg "Checking for NVIDIA GPU..."
        detect::gpu_pkgs st_gpu_pkgs || return 1
    else
        debug_msg "DRY-RUN: NVIDIA detection skipped (canonical absence)"
    fi
    if (( ${#st_gpu_pkgs[@]} > 0 )); then
        status_msg "NVIDIA GPU detected: ${st_gpu_pkgs[*]}"
        status_msg "Configuring nvidia-open-dkms sleep/hibernate handling..."
        services::nvidia_pm "$TARGET_MNT" || return 1
        success_msg "Enabled NVIDIA suspend, hibernate, and resume services"
    else
        status_msg "No NVIDIA GPU detected. Skipping NVIDIA sleep configuration"
    fi

    local st_hib_delay
    st_hib_delay="$(defaults::get hybrid_sleep_delay)"
    st_hib_delay="${st_hib_delay:-15min}"   # guards an empty override
    services::hibernation_configure "$TARGET_MNT" "$st_hib_delay" || return 1

    status_msg "Optional SSH configuration..."
    if ui::confirm ssh_enable "Enable SSH server with key-only authentication?" "no"; then
        local st_user st_key
        st_user="$(state_get users/user "")"
        [[ -n "$st_user" ]] || {
            error_msg "stage 14 SSH needs users/user (stage 10)"
            return 1
        }
        st_key="$(ui::input --placeholder "/path/to/your/public-key.pub")"
        services::ssh_harden "$TARGET_MNT" "$st_user" "$st_key" || return 1
        state_set "services/ssh_user" "$st_user"
        success_msg "SSH enabled for '$st_user' with validated key-only authentication"
    else
        status_msg "SSH server not selected; no remote-access firewall rule added"
    fi

    state_set "services/done" "done"
    success_msg "Essential services configured"
    return 0
}
