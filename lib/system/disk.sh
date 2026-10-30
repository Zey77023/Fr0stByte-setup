#!/bin/bash

# Block-device APIs

if [[ ${_SOURCED_system_disk:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_system_disk="loaded"

module::provide system.disk \
    disk::enumerate disk::normalize_media_name disk::part_type \
    disk::size_bytes disk::is_mounted disk::probe disk::verify_layout \
    disk::partition_auto disk::row_device

# Partition-type GUIDs.
declare -gr _DISK_EFI_PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
declare -gr _DISK_LINUXFS_PARTTYPE="0fc63daf-8483-4772-8e79-3d69d8477de4"

# disk::normalize_media_name <name>
disk::normalize_media_name() {
    local bare="$1"
    if [[ $bare =~ ^(nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ $bare =~ ^(mmcblk[0-9]+)p[0-9]+$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ $bare =~ ^(s|v|h)d[a-z]+[0-9]+$ ]]; then
        printf '%s\n' "${bare%%[0-9]*}"
    else
        printf '%s\n' "$bare"
    fi
    return 0
}

# disk::enumerate <out_var>
disk::enumerate() {
    local -n out_disks="$1"
    local installer_media line bare
    local -a probe_disks=()

    installer_media=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null)" 2>/dev/null | head -n1)
    if [[ -z "$installer_media" ]]; then
        bare=$(basename -- "$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null)" 2>/dev/null)
        installer_media=$(disk::normalize_media_name "$bare")
    fi
    debug_msg "Detected installer media to exclude: $installer_media"

    mapfile -t probe_disks < <(
        lsblk -d -n -p -o NAME,SIZE,MODEL,TRAN 2>/dev/null |
        grep -Ev '/loop|/rom' |
        grep -vE "^/dev/${installer_media}([[:space:]]|$)" |
        awk '{
            # lsblk columns are space-separated but MODEL may contain
            # spaces, and an empty TRAN leaves no trailing column at
            # all — so only treat the last field as a transport when it
            # actually names one; otherwise the model spans $3..$NF.
            if (NF <= 2) { print $1 " " $2; next }
            tran = ""; model = ""
            if ($NF ~ /^(sata|nvme|usb|mmc|sas|scsi|ide|virtio|sdio|fibre|fcoe|fc|ata)$/) {
                tran = $NF
                for (i = 3; i < NF; i++)
                    model = model (model == "" ? "" : " ") $i
            } else {
                for (i = 3; i <= NF; i++)
                    model = model (model == "" ? "" : " ") $i
            }
            m = (model != "") ? " [" model "]" : ""
            t = (tran != "") ? " (" tran ")" : ""
            print $1 " " $2 m t
        }'
    )

    ((${#probe_disks[@]} > 0)) || {
        error_msg "No storage devices detected"
        return 1
    }
    out_disks=("${probe_disks[@]}")
    return 0
}

# disk::part_type <dev>  (prints lowercased PARTTYPE)
disk::part_type() {
    lsblk -no PARTTYPE "$1" | tr '[:upper:]' '[:lower:]'
}

# disk::size_bytes <dev>
disk::size_bytes() {
    blockdev --getsize64 "$1"
}

# disk::is_mounted <dev>  (rc 0 = has mountpoints)
disk::is_mounted() {
    lsblk -nrpo MOUNTPOINTS "$1" | awk 'NF { found=1 } END { exit found ? 0 : 1 }'
}

# disk::probe <dev> — partprobe + udev settle so the new partitions exist.
disk::probe() {
    exec_cmd partprobe "$1" || return 1
    exec_cmd udevadm settle || return 1
    return 0
}

# disk::verify_layout <disk> <boot_label> <root_label>
disk::verify_layout() {
    local disk="$1" boot_label="$2" root_label="$3"

    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        printf '%s\n' "${disk}1" "${disk}2"
        return 0
    fi
    local -a boot_parts=() root_parts=()
    local boot_root_size root_root_size

    mapfile -t boot_parts < <(lsblk -lp -o NAME,PARTLABEL "$disk" | awk -v label="$boot_label" '$2 == label {print $1}')
    mapfile -t root_parts < <(lsblk -lp -o NAME,PARTLABEL "$disk" | awk -v label="$root_label" '$2 == label {print $1}')

    ((${#boot_parts[@]} == 1 && ${#root_parts[@]} == 1)) || {
        error_msg "Expected exactly one EFI and one ROOT partition after partitioning."
        return 1
    }
    [[ -n "${boot_parts[0]}" && -n "${root_parts[0]}" ]] || {
        error_msg "Could not find partitions on $disk after creation."
        return 1
    }

    [[ "$(disk::part_type "${boot_parts[0]}")" == "$_DISK_EFI_PARTTYPE" ]] || {
        error_msg "Created boot partition has an unexpected partition type"
        return 1
    }
    [[ "$(disk::part_type "${root_parts[0]}")" == "$_DISK_LINUXFS_PARTTYPE" ]] || {
        error_msg "Created root partition has an unexpected partition type"
        return 1
    }
    boot_root_size=$(disk::size_bytes "${boot_parts[0]}")
    ((${boot_root_size:-0} >= 2 * 1024 * 1024 * 1024)) || {
        error_msg "EFI partition is smaller than 2 GiB"
        return 1
    }
    root_root_size=$(disk::size_bytes "${root_parts[0]}")
    ((${root_root_size:-0} > 1024 * 1024 * 1024)) || {
        error_msg "Root partition is too small"
        return 1
    }

    printf '%s\n' "${boot_parts[0]}" "${root_parts[0]}"
    return 0
}

# disk::partition_auto <disk> <boot_label> <root_label> <out_boot> <out_root>
#   Full wipe + 2G ESP + root; verifies the layout; sets namerefs.
disk::partition_auto() {
    local disk="$1" boot_label="$2" root_label="$3"
    local -n out_boot="$4"
    local -n out_root="$5"
    local -a found=()

    ui::spin "Clearing partition table on $disk..." -- sgdisk -Z "$disk" || return 1
    ui::spin "Creating EFI partition..." -- \
        sgdisk -n 1:0:+2G -t 1:ef00 -c 1:"$boot_label" "$disk" || return 1
    ui::spin "Creating root partition..." -- \
        sgdisk -n 2:0:0 -t 2:8300 -c 2:"$root_label" "$disk" || return 1

    if ! ui::spin "Refreshing partition table..." -- disk::probe "$disk"; then
        return 1
    fi
    exec_cmd sgdisk -v "$disk" || return 1

    mapfile -t found < <(disk::verify_layout "$disk" "$boot_label" "$root_label") || return 1
    out_boot="${found[0]}"
    out_root="${found[1]}"
    success_msg "Found: Boot -> $out_boot | Root -> $out_root"
    return 0
}

# disk::row_device <row> — first field of a lsblk row.
disk::row_device() {
    cut -f1 <<<"$1"
}

return 0
