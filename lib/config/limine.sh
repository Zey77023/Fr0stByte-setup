#!/bin/bash

# Limine bootloader

if [[ ${_SOURCED_config_limine:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_limine="loaded"

module::provide config.limine limine::configure limine::install_hook \
    limine::install limine::hidden_menu limine::assert_assets

# limine::configure <mnt> <luks_uuid> <luks_name> <resume_offset>
#   Writes /etc/default/limine with the kernel cmdline (rd.luks.name,
#   resume, resume_offset, zswap disabled).
limine::configure() {
    local mnt="$1" luks_uuid="$2" luks_name="$3" resume_offset="$4"
    local conf="$mnt/etc/default/limine"

    [[ -n "$luks_uuid" ]] || {
        error_msg "LUKS UUID not provided; cannot configure Limine kernel cmdline"
        return 1
    }
    [[ -n "$luks_name" && -n "$resume_offset" ]] || {
        error_msg "limine::configure: luks_name and resume_offset are required"
        return 1
    }

    exec_cmd mkdir -p "$(dirname "$conf")" || return 1
    exec_cmd tee "$conf" >/dev/null <<EOS
TARGET_OS_NAME="Fr0stByte"
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=@ rootfstype=btrfs rd.luks.name=${luks_uuid}=${luks_name} root=/dev/mapper/${luks_name} resume=/dev/mapper/${luks_name} resume_offset=${resume_offset} zswap.enabled=0"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
EOS
    debug_msg "limine: wrote $conf (resume_offset=$resume_offset)"
    return 0
}

# limine::install_hook <mnt> — install the mkinitcpio hook package.
limine::install_hook() {
    ui::spin "Installing limine-mkinitcpio-hook..." \
        -- chroot_exec "$1" -- pacman -S --needed --noconfirm limine-mkinitcpio-hook
}

# limine::install <mnt> — run limine-install inside the chroot.
limine::install() {
    chroot_exec "$1" -- limine-install
}

# limine::__limine_conf_gate <conf>
limine::__limine_conf_gate() {
    [[ -f $1 ]] && return 0
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: $1 absent; hidden-menu appends journal-only"
        return 0
    fi
    error_msg "limine.conf not found at $1; install limine-mkinitcpio-hook first"
    return 1
}

# limine::hidden_menu <mnt>
#   append the global timeout/quiet directives idempotently AFTER
#   the hook has generated /boot/limine.conf.
limine::hidden_menu() {
    local mnt="$1"
    local conf="$mnt/boot/limine.conf"

    limine::__limine_conf_gate "$conf" || return 1

    if grep -qE '^[[:space:]]*timeout:' "$conf"; then
        exec_cmd sed -i 's/^[[:space:]]*timeout:.*/timeout: 1/' "$conf"
    else
        exec_cmd sed -i '1i timeout: 1' "$conf"
    fi

    if grep -qE '^[[:space:]]*#*[[:space:]]*quiet:' "$conf"; then
        exec_cmd sed -i 's/^[[:space:]]*#*[[:space:]]*quiet:.*/quiet: yes/' "$conf"
    else
        exec_cmd sed -i '1i quiet: yes' "$conf"
    fi

    debug_msg "limine: hidden-menu directives present in $conf"
    return 0
}

# limine::assert_assets <mnt> — EFI payloads presence check
limine::assert_assets() {
    local mnt="$1" count
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: assuming limine-install produced payloads in $mnt/boot/EFI"
        return 0
    fi
    count=$(find "$mnt/boot/EFI" -type f \( -iname '*.efi' -o -iname 'limine*' \) -printf '.' 2>/dev/null | wc -c)
    ((count > 0)) || {
        error_msg "Limine installation did not produce an EFI payload under $mnt/boot/EFI"
        return 1
    }
    return 0
}

return 0
