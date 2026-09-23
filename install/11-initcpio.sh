#!/bin/bash

debug_msg "Starting initcpio configuration stage"

status_msg "Configuring mkinitcpio for Btrfs..."

MKINIT_CONF="$TARGET_MNT/etc/mkinitcpio.conf"
require_paths "$MKINIT_CONF"

cp "$MKINIT_CONF" "$MKINIT_CONF.bak"

# CPU vendor / microcode image path
MICROCODE_BIN=$(cpu_microcode_img) || {
    error_msg "CPU microcode vendor detection failed"
    exit 1
}
[[ -n "$MICROCODE_BIN" ]] && status_msg "Microcode image: $MICROCODE_BIN"
debug_msg "Microcode binary: $MICROCODE_BIN"

# Add btrfs to MODULES
if grep -q '^MODULES=' "$MKINIT_CONF"; then
    if ! grep -q 'MODULES=.*\bbtrfs\b' "$MKINIT_CONF"; then
        sed -i 's/^MODULES=(/MODULES=(btrfs /' "$MKINIT_CONF"
        status_msg "Added 'btrfs' to MODULES"
    else
        status_msg "'btrfs' already present in MODULES"
    fi
else
    echo 'MODULES=(btrfs)' >>"$MKINIT_CONF"
    status_msg "Created MODULES line with 'btrfs'"
fi

# Add /usr/bin/btrfs to BINARIES
for bin in "/usr/bin/btrfs"; do
    [[ -n "$bin" ]] || continue
    if grep -q '^BINARIES=' "$MKINIT_CONF"; then
        if ! grep -q "BINARIES=.*${bin}\b" "$MKINIT_CONF"; then
            sed -i "s|^BINARIES=(|BINARIES=(${bin} |" "$MKINIT_CONF"
            status_msg "Added '$bin' to BINARIES"
        else
            status_msg "'$bin' already present in BINARIES"
        fi
    else
        echo "BINARIES=(${bin})" >>"$MKINIT_CONF"
        status_msg "Created BINARIES line with '$bin'"
    fi
done

case "$MICROCODE_BIN" in
    /boot/intel-ucode.img)
        MICROCODE_PACKAGE="intel-ucode"
        ;;
    /boot/amd-ucode.img)
        MICROCODE_PACKAGE="amd-ucode"
        ;;
    *)
        error_msg "Could not determine the expected microcode package"
        exit 1
        ;;
esac
chroot_exec pacman -Q "$MICROCODE_PACKAGE"
[[ -s "$TARGET_MNT$MICROCODE_BIN" ]] || {
    error_msg "Expected microcode image is missing: $TARGET_MNT$MICROCODE_BIN"
    exit 1
}
success_msg "Verified $MICROCODE_PACKAGE and $MICROCODE_BIN"

if chroot_exec --expect "0 1" pacman -Q nvidia-open-dkms; then
    if [[ $CHROOT_EXEC_EXIT_CODE -eq 0 ]]; then
        NVIDIA_MODULE_COUNT=$(find "$TARGET_MNT/usr/lib/modules" -type f -name 'nvidia.ko*' -printf '.' 2>/dev/null | wc -c)
        (( NVIDIA_MODULE_COUNT > 0 )) || {
            error_msg "nvidia-open-dkms is installed but produced no kernel modules"
            exit 1
        }
        if ! grep -Eq '^MODULES=.*nvidia_drm' "$MKINIT_CONF"; then
            if grep -q '^MODULES=' "$MKINIT_CONF"; then
                sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$MKINIT_CONF"
            else
                echo 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' >>"$MKINIT_CONF"
            fi
            status_msg "Added NVIDIA modules for early KMS"
        else
            status_msg "NVIDIA modules already configured for early KMS"
        fi
    fi
fi

# Ensure 'sd-encrypt' hook is in HOOKS
if grep -q '^[[:space:]]*HOOKS=' "$MKINIT_CONF"; then
    if ! grep -q '^[[:space:]]*HOOKS=.*\<sd-encrypt\>' "$MKINIT_CONF"; then
        sed -i -E 's/^([[:space:]]*HOOKS=.*\bblock\b)(.*\bfilesystems\b.*)$/\1 sd-encrypt\2/' "$MKINIT_CONF"
        status_msg "Inserted 'sd-encrypt' after 'block' in HOOKS"
    else
        status_msg "'sd-encrypt' hook already present in HOOKS"
    fi

    # Add 'resume' hook after 'sd-encrypt' for hibernation
    if ! grep -q '^[[:space:]]*HOOKS=.*\<resume\>' "$MKINIT_CONF"; then
        sed -i -E 's/^([[:space:]]*HOOKS=.*\bsd-encrypt\b)(.*\bfilesystems\b.*)$/\1 resume\2/' "$MKINIT_CONF"
        status_msg "Inserted 'resume' hook after 'sd-encrypt' in HOOKS"
    else
        status_msg "'resume' hook already present in HOOKS"
    fi
else
    echo 'HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block sd-encrypt resume filesystems fsck)' >>"$MKINIT_CONF"
    status_msg "Created HOOKS line with 'sd-encrypt' and 'resume'"
fi

# Regenerate initramfs
status_msg "Regenerating initramfs (mkinitcpio -P)..."
chroot_exec mkinitcpio -P
chroot_exec sh -c 'grep -Eq "(^|[[:space:]])sd-encrypt([[:space:]]|$)" /etc/mkinitcpio.conf'
chroot_exec sh -c 'grep -Eq "(^|[[:space:]])resume([[:space:]]|$)" /etc/mkinitcpio.conf'

INITRAMFS_COUNT=$(find "$TARGET_MNT/boot" -maxdepth 1 -type f -name 'initramfs-*.img' -printf '.' 2>/dev/null | wc -c)
(( INITRAMFS_COUNT > 0 )) || {
    error_msg "mkinitcpio did not produce an initramfs image in $TARGET_MNT/boot"
    exit 1
}

success_msg "mkinitcpio configured for Btrfs and initramfs rebuilt"
