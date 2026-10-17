#!/bin/bash

load_pkglist() {
    local list_file="$1" line package

    PKGS=()
    debug_msg "Loading package list from: $list_file"
    [[ -f "$list_file" ]] || {
        error_msg "Package list does not exist: $list_file"
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        package="${line%%[[:space:]]*}"
        [[ "$package" == "$line" && "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9@._+:-]*$ ]] || {
            error_msg "Invalid package name in $list_file: $line"
            return 1
        }
        append_package_once "$package"
    done <"$1"
    debug_msg "Loaded ${#PKGS[@]} packages: ${PKGS[*]}"
}

cpu_microcode_img() {
    debug_msg "Detecting CPU microcode image path"
    case "$("$INSTALLER_UTILS/get-cpu-vendor.sh")" in
    intel)
        echo "/boot/intel-ucode.img"
        debug_msg "Intel CPU detected"
        ;;
    amd)
        echo "/boot/amd-ucode.img"
        debug_msg "AMD CPU detected"
        ;;
    *)
        debug_msg "Unknown CPU vendor"
        return 1
        ;;
    esac
}

append_package_once() {
    local package="$1"
    local existing

    for existing in "${PKGS[@]}"; do
        [[ "$existing" == "$package" ]] && return 0
    done
    PKGS+=("$package")
}

install_packages_from_list() {
    local list_file="$1"
    debug_msg "Installing packages from list: $list_file"
    load_pkglist "$list_file" || return 1

    if [[ ${#PKGS[@]} -eq 0 ]]; then
        warn_msg "No packages found in $list_file"
        return 0
    fi

    debug_msg "Installing ${#PKGS[@]} packages: ${PKGS[*]}"
    status_msg "Installing packages..."
    pacman -S --needed --noconfirm "${PKGS[@]}"
    success_msg "Package installation complete"
}

install_packages_from_list_in_chroot() {
    local list_file="$1"
    debug_msg "Installing packages from list to chroot: $list_file"
    load_pkglist "$list_file" || return 1

    if [[ ${#PKGS[@]} -eq 0 ]]; then
        warn_msg "No packages found in $list_file"
        return 0
    fi

    debug_msg "Installing ${#PKGS[@]} packages to chroot: ${PKGS[*]}"
    status_msg "Installing packages to chroot..."
    chroot_exec pacman -S --needed --noconfirm "${PKGS[@]}"
    success_msg "Package installation to chroot complete"
}

add_cpu_microcode() {
    debug_msg "Detecting CPU vendor for microcode package"
    local vendor
    vendor="$("$INSTALLER_UTILS/get-cpu-vendor.sh")"
    debug_msg "CPU vendor detected: $vendor"

    case "$vendor" in
    intel)
        PKGS+=(intel-ucode)
        debug_msg "Added intel-ucode to package list"
        ;;
    amd)
        PKGS+=(amd-ucode)
        debug_msg "Added amd-ucode to package list"
        ;;
    *)
        error_msg "Unsupported or unknown CPU vendor; refusing to install without microcode"
        return 1
        ;;
    esac
}

add_hardware_packages() {
    local gpu

    command -v lspci >/dev/null 2>&1 || {
        error_msg "pciutils is required for hardware detection"
        return 1
    }

    gpu=$(lspci -nn | grep -i 'VGA compatible controller\|3D controller\|Display controller' | head -n1 || true)
    if [[ "$gpu" == *NVIDIA* ]]; then
        status_msg "NVIDIA GPU detected; selecting nvidia-open-dkms for linux-zen"
        append_package_once linux-zen-headers
        append_package_once nvidia-open-dkms
        append_package_once nvidia-utils
    else
        debug_msg "No NVIDIA GPU detected; no NVIDIA driver packages selected"
    fi
}
