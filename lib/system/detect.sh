#!/bin/bash

# Hardware-detection APIs: CPU/GPU/microcode, host side.
# Detection runs at install time on the target.

if [[ ${_SOURCED_system_detect:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_system_detect="loaded"

module::provide system.detect \
    detect::cpu_vendor detect::microcode_pkg detect::microcode_img \
    detect::gpu_pkgs detect::nvidia_modules_present

# detect::cpu_vendor <out_var> — intel / amd / unknown.
detect::cpu_vendor() {
    local -n out_vendor="$1"
    local vendor_id
    vendor_id="$(grep -m 1 "vendor_id" /proc/cpuinfo | awk '{print $3}' || true)"
    case "$vendor_id" in
    GenuineIntel) out_vendor="intel" ;;
    AuthenticAMD) out_vendor="amd" ;;
    *) out_vendor="unknown" ;;
    esac
    debug_msg "CPU vendor detected: $out_vendor"
    return 0
}

# detect::microcode_pkg <out_var> — intel-ucode / amd-ucode.
detect::microcode_pkg() {
    local -n out_pkg="$1"
    local vendor
    detect::cpu_vendor vendor || return 1
    case "$vendor" in
    intel) out_pkg="intel-ucode" ;;
    amd) out_pkg="amd-ucode" ;;
    *)
        error_msg "Unsupported or unknown CPU vendor; refusing to install without microcode"
        return 1
        ;;
    esac
    return 0
}

# detect::microcode_img <out_var> — /boot/intel-ucode.img or /boot/amd-ucode.img.
detect::microcode_img() {
    local -n out_img="$1"
    local vendor
    detect::cpu_vendor vendor || return 1
    case "$vendor" in
    intel)
        out_img="/boot/intel-ucode.img"
        debug_msg "Intel CPU detected"
        ;;
    amd)
        out_img="/boot/amd-ucode.img"
        debug_msg "AMD CPU detected"
        ;;
    *)
        debug_msg "Unknown CPU vendor"
        return 1
        ;;
    esac
    return 0
}

# detect::gpu_pkgs <out_array_var> — NVIDIA driver set when detected.
detect::gpu_pkgs() {
    local -n out_pkgs="$1"
    local gpu_probe
    command -v lspci >/dev/null 2>&1 || {
        error_msg "pciutils is required for hardware detection"
        return 1
    }
    gpu_probe=$(lspci -nn | grep -i 'VGA compatible controller\|3D controller\|Display controller' | head -n1 || true)
    if [[ "$gpu_probe" == *NVIDIA* ]]; then
        status_msg "NVIDIA GPU detected; selecting nvidia-open-dkms for linux-zen"
        out_pkgs=(linux-zen-headers nvidia-open-dkms nvidia-utils)
    else
        debug_msg "No NVIDIA GPU detected; no NVIDIA driver packages selected"
        out_pkgs=()
    fi
    return 0
}

# detect::nvidia_modules_present <mnt> — rc 0 when nvidia.ko* exists.
detect::nvidia_modules_present() {
    local mnt="$1" count
    count=$(find "$mnt/usr/lib/modules" -type f -name 'nvidia.ko*' -printf '.' 2>/dev/null | wc -c)
    ((count > 0))
}
