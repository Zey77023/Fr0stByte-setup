#!/bin/bash

debug_msg "Starting services configuration stage"

status_msg "Enabling essential system services..."

# NetworkManager
chroot_exec systemctl enable NetworkManager
chroot_exec --expect "0 1" systemctl disable dhcpcd.service
if [[ $CHROOT_EXEC_EXIT_CODE -eq 0 ]]; then
    status_msg "Disabled competing dhcpcd service"
fi
success_msg "NetworkManager enabled"

# Firewall
status_msg "Configuring UFW firewall policy..."
chroot_exec ufw default deny incoming
chroot_exec ufw default allow outgoing
chroot_exec ufw --force enable
chroot_exec systemctl enable ufw
chroot_exec ufw status verbose
success_msg "UFW enabled with deny-incoming and allow-outgoing defaults"

# Zram configuration
status_msg "Configuring zram..."
ZRAM_CONF="$TARGET_MNT/etc/systemd/zram-generator.conf"
ZRAM_SIZE="${ZRAM_SIZE:-ram/2}"
ZRAM_COMPRESSION="${ZRAM_COMPRESSION:-zstd}"
[[ "$ZRAM_SIZE" =~ ^(ram|ram/[0-9]+|[0-9]+[KMG]?)$ ]] || {
    error_msg "Invalid ZRAM_SIZE: $ZRAM_SIZE"
    exit 1
}
[[ "$ZRAM_COMPRESSION" =~ ^[a-zA-Z0-9_-]+$ ]] || {
    error_msg "Invalid ZRAM_COMPRESSION: $ZRAM_COMPRESSION"
    exit 1
}
mkdir -p "$(dirname "$ZRAM_CONF")"
cat >"$ZRAM_CONF" <<EOF
[zram0]
zram-size = $ZRAM_SIZE
compression-algorithm = $ZRAM_COMPRESSION
swap-priority = 100
fs-type = swap
EOF
grep -Fxq "zram-size = $ZRAM_SIZE" "$ZRAM_CONF"
grep -Fxq "compression-algorithm = $ZRAM_COMPRESSION" "$ZRAM_CONF"
success_msg "Zram-generator configured at $ZRAM_CONF ($ZRAM_SIZE, $ZRAM_COMPRESSION)"

if gum confirm "Install optional hardware and performance diagnostic tools?" --default=no; then
    DIAGNOSTIC_LIST="$INSTALLER_ROOT/optional-diagnostic-packages"
    install_packages_from_list_in_chroot "$DIAGNOSTIC_LIST"
    success_msg "Optional diagnostic tools installed"
else
    status_msg "Optional diagnostic tools not installed"
fi

# TODO: Make a dedicated subvol for swapfile, it has to be nodatacow and disabled compression. Then use the btrfs tool to create a new swapfile.
# TODO: Chmod it to 600 and then add it to ftsab with priority set to -1.
# TODO: Setup for hybrid sleep is required when using NVIDIA GPU.

# Swap file for hibernation
status_msg "Configuring swap file for hibernation..."
ensure_fstab_entry "$TARGET_MNT/etc/fstab" "$MAPPER_DEV" "/swap" "btrfs" \
    "subvol=@swap,nodatacow,discard=async" "0" "0"
ensure_fstab_entry "$TARGET_MNT/etc/fstab" "/swap/swapfile" "none" "swap" \
    "defaults" "0" "0"
[[ "$(fstab_entry_count "$TARGET_MNT/etc/fstab" "$MAPPER_DEV" "/swap" "btrfs")" -eq 1 ]] || {
    error_msg "Swap subvolume entry is missing or duplicated"
    exit 1
}
[[ "$(fstab_entry_count "$TARGET_MNT/etc/fstab" "/swap/swapfile" "none" "swap")" -eq 1 ]] || {
    error_msg "Swapfile entry is missing or duplicated"
    exit 1
}
chroot_exec findmnt --verify --tab-file /etc/fstab
success_msg "Swap subvolume and swapfile entries are configured in fstab"

# NVIDIA GPU detection and sleep/hibernate handling
status_msg "Checking for NVIDIA GPU..."
NVIDIA_GPU=$(lspci -nn | grep -i nvidia | head -n1 || true)

if [[ -n "$NVIDIA_GPU" ]]; then
    status_msg "NVIDIA GPU detected: $NVIDIA_GPU"
    status_msg "Configuring nvidia-open-dkms sleep/hibernate handling..."

    chroot_exec --expect "0 1" pacman -Q nvidia-open-dkms
    [[ $CHROOT_EXEC_EXIT_CODE -eq 0 ]] || {
        error_msg "NVIDIA hardware was detected but nvidia-open-dkms is not installed"
        exit 1
    }
    chroot_exec pacman -Q nvidia-utils

    NVIDIA_PM_CONF="$TARGET_MNT/etc/modprobe.d/nvidia.conf"
    mkdir -p "$(dirname "$NVIDIA_PM_CONF")" "$TARGET_MNT/var/tmp"
    cat >"$NVIDIA_PM_CONF" <<'EOF'
options nvidia_drm modeset=1
options nvidia_drm fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
EOF
    success_msg "Configured NVIDIA DRM modesetting and video-memory preservation"

    for service in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
        chroot_exec systemctl enable "$service"
        chroot_exec systemctl is-enabled "$service"
    done
    success_msg "Enabled packaged NVIDIA suspend, hibernate, and resume services"

    status_msg "Rebuilding initramfs with NVIDIA power-management configuration..."
    chroot_exec mkinitcpio -P
else
    status_msg "No NVIDIA GPU detected. Skipping NVIDIA sleep configuration"
fi

# SSH hardening
status_msg "Optional SSH configuration..."
if gum confirm "Enable SSH server with key-only authentication?" --default=no; then
    SSH_PUBLIC_KEY=$(gum input --placeholder "/path/to/your/public-key.pub")
    [[ -f "$SSH_PUBLIC_KEY" ]] || {
        error_msg "SSH public key does not exist: ${SSH_PUBLIC_KEY:-<empty>}"
        exit 1
    }
    ssh-keygen -lf "$SSH_PUBLIC_KEY" >/dev/null || {
        error_msg "SSH public key could not be validated"
        exit 1
    }
    grep -Eq '^(ssh-(ed25519|rsa|ecdsa)|sk-ssh-ed25519|sk-ecdsa-sha2-nistp256)[[:space:]]' "$SSH_PUBLIC_KEY" || {
        error_msg "SSH key is not a supported authorized_keys public-key line"
        exit 1
    }

    chroot_exec pacman -S --needed --noconfirm openssh
    chroot_exec install -d -m 700 -o "$NEW_USER" -g "$NEW_USER" "/home/$NEW_USER/.ssh"
    install -m 600 "$SSH_PUBLIC_KEY" "$TARGET_MNT/home/$NEW_USER/.ssh/authorized_keys"
    chroot_exec chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh/authorized_keys"

    SSH_DROPIN="$TARGET_MNT/etc/ssh/sshd_config.d/10-fr0stbyte-key-only.conf"
    mkdir -p "$(dirname "$SSH_DROPIN")"
    cat >"$SSH_DROPIN" <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $NEW_USER
EOF
    chroot_exec sshd -t
    chroot_exec systemctl enable sshd.service
    chroot_exec ufw allow ssh
    chroot_exec ufw status verbose
    success_msg "SSH enabled for '$NEW_USER' with validated key-only authentication"
else
    status_msg "SSH server not selected; no remote-access firewall rule added"
fi

success_msg "Essential services configured"
