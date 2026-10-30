#!/bin/bash
# fstab generation: genfstab -U + findmnt verification.

if [[ ${_SOURCED_config_genfstab:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_config_genfstab="loaded"

module::provide config.genfstab genfstab::write

# genfstab::write <mnt>
#   genfstab -U into <mnt>/etc/fstab + findmnt verification in chroot.
genfstab::write() {
    local mnt="$1"
    exec_cmd mkdir -p "$mnt/etc" || return 1
    if ! ui::spin "Generating fstab for the target system..." -- \
        sh -c "genfstab -U '$mnt' > '$mnt/etc/fstab'"; then
        error_msg "genfstab run failed"
        return 1
    fi
    chroot_exec "$mnt" -- findmnt --verify --tab-file /etc/fstab || {
        error_msg "Generated fstab failed findmnt verification"
        return 1
    }
    return 0
}

return 0
