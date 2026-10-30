#!/bin/bash
# systemd services + firewall + GPU power management + hybrid-sleep drop-in.

if [[ ${_SOURCED_config_services:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_services="loaded"

module::provide config.services services::svc_enable services::svc_disable \
    services::ufw_policy services::zram_conf services::nvidia_pm \
    services::ssh_harden services::hibernation_configure

function services::svc_enable() {
    chroot_exec "$1" -- systemctl enable "$2"
}

# services::svc_disable <mnt> <unit> — expected rc "0 1" (1 = not installed).
services::svc_disable() {
    local mnt="$1" unit="$2" rc=0
    chroot_exec "$mnt" --expect "0 1" --code rc -- systemctl disable "$unit" || {
        error_msg "systemctl disable $unit failed unexpectedly"
        return 2
    }
    [[ "$rc" == "0" ]]
}

# services::ufw_policy <mnt> — deny incoming / allow outgoing / enable.
services::ufw_policy() {
    local mnt="$1"
    chroot_exec "$mnt" -- ufw default deny incoming || return 1
    chroot_exec "$mnt" -- ufw default allow outgoing || return 1
    chroot_exec "$mnt" -- ufw --force enable || return 1
    chroot_exec "$mnt" -- systemctl enable ufw || return 1
    chroot_exec "$mnt" -- ufw status verbose
    return 0
}

# services::zram_conf <mnt> <size> <compression>
services::zram_conf() {
    local mnt="$1" size="$2" compression="$3"
    local conf="$mnt/etc/systemd/zram-generator.conf"

    [[ "$size" =~ ^(ram|ram/[0-9]+|[0-9]+[KMG]?)$ ]] || {
        error_msg "Invalid zram size: $size"
        return 1
    }
    [[ "$compression" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        error_msg "Invalid zram compression algorithm: $compression"
        return 1
    }
    exec_cmd mkdir -p "$(dirname "$conf")" || return 1
    exec_cmd tee "$conf" >/dev/null <<EOS
[zram0]
zram-size = $size
compression-algorithm = $compression
swap-priority = 100
fs-type = swap
EOS
    return 0
}

# services::nvidia_pm <mnt>
#   NVIDIA power management: modprobe options + suspend/hibernate/resume
#   services + initramfs rebuild. Requires nvidia-open-dkms installed —
#   rc 2 when the package is missing.
services::nvidia_pm() {
    local mnt="$1" rc=0
    chroot_exec "$mnt" --expect "0 1" --code rc -- pacman -Q nvidia-open-dkms || {
        error_msg "nvidia-open-dkms probe failed unexpectedly"
        return 2
    }
    [[ "$rc" == "0" ]] || {
        error_msg "NVIDIA hardware was detected but nvidia-open-dkms is not installed"
        return 2
    }
    chroot_exec "$mnt" -- pacman -Q nvidia-utils || return 1

    local conf="$mnt/etc/modprobe.d/nvidia.conf"
    exec_cmd mkdir -p "$(dirname "$conf")" "$mnt/var/tmp" || return 1
    exec_cmd tee "$conf" >/dev/null <<'EOF'
options nvidia_drm modeset=1
options nvidia_drm fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
EOF
    local svc
    for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
        services::svc_enable "$mnt" "$svc" || return 1
        chroot_exec "$mnt" -- systemctl is-enabled "$svc" || return 1
    done
    initramfs::rebuild "$mnt" || return 1
    return 0
}

# services::ssh_harden <mnt> <user> <authorized_key_path>
#   Host-side validation (key file) + chroot-side setup; sshd -t
#   + ufw rule; enables sshd.
services::ssh_harden() {
    local mnt="$1" user="$2" key_path="$3"
    local dropin

    [[ -f "$key_path" ]] || {
        error_msg "SSH public key does not exist: $key_path"
        return 1
    }
    ssh-keygen -lf "$key_path" >/dev/null || {
        error_msg "SSH public key could not be validated"
        return 1
    }
    grep -Eq '^(ssh-(ed25519|rsa|ecdsa)|sk-ssh-ed25519|sk-ecdsa-sha2-nistp256)[[:space:]]' "$key_path" || {
        error_msg "SSH key is not a supported authorized_keys public-key line"
        return 1
    }

    pacman::target "$mnt" -S --needed --noconfirm openssh || return 1
    chroot_exec "$mnt" -- install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh" || return 1
    exec_cmd install -m 600 "$key_path" "$mnt/home/$user/.ssh/authorized_keys" || return 1
    chroot_exec "$mnt" -- chown "$user:$user" "/home/$user/.ssh/authorized_keys" || return 1

    dropin="$mnt/etc/ssh/sshd_config.d/10-fr0stbyte-key-only.conf"
    exec_cmd mkdir -p "$(dirname "$dropin")" || return 1
    exec_cmd tee "$dropin" >/dev/null <<EOS
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $user
EOS
    chroot_exec "$mnt" -- sshd -t || return 1
    services::svc_enable "$mnt" sshd.service || return 1
    chroot_exec "$mnt" -- ufw allow ssh || return 1
    return 0
}

# services::hibernation_configure <mnt> <delay>
#   hybrid sleep: drop-in with SuspendThenHibernate allowed and the
#   HibernateDelaySec taken from defaults.conf hybrid_sleep_delay.
services::hibernation_configure() {
    local mnt="$1" delay="$2"
    local conf="$mnt/etc/systemd/sleep.conf.d/10-fr0stbyte-hibernate.conf"

    [[ -n "$delay" ]] || {
        error_msg "hybrid_sleep_delay is empty; refusing to write the hybrid-sleep drop-in"
        return 1
    }
    exec_cmd mkdir -p "$(dirname "$conf")" || return 1
    exec_cmd tee "$conf" >/dev/null <<EOS
[Sleep]
AllowSuspendThenHibernate=yes
HibernateDelaySec=$delay
EOS
    debug_msg "services: hybrid-sleep drop-in written ($conf, delay=$delay)"
    return 0
}

return 0
