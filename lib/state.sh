#!/bin/bash

# Shared installer state. Stages may update these values as resources are
# created; cleanup only acts on resources registered by this installer run.
: "${TARGET_MNT:=/mnt}"
: "${LUKS_NAME:=cryptroot}"
: "${MAPPER_DEV:=/dev/mapper/$LUKS_NAME}"
: "${EFI_UUID:=c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
: "${LINUX_FS_UUID:=0fc63daf-8483-4772-8e79-3d69d8477de4}"
: "${BOOT_LABEL:=FROSTEFI}"
: "${ROOT_LABEL:=FROSTROOT}"
: "${TARGET_DISK:=}"
: "${TARGET_BOOT:=}"
: "${TARGET_ROOT:=}"
: "${LUKS_UUID:=}"
: "${INSTALLER_STATE_FILE:=/run/fr0stbyte-installer.state}"

export TARGET_MNT 
export LUKS_NAME 
export MAPPER_DEV 
export EFI_UUID 
export LINUX_FS_UUID 
export BOOT_LABEL 
export ROOT_LABEL 
export TARGET_DISK 
export TARGET_BOOT 
export TARGET_ROOT 
export LUKS_UUID
export INSTALLER_STATE_FILE

declare -ag INSTALLER_MOUNTS=()
declare -ag INSTALLER_MAPPERS=()

mkdir -p "$(dirname -- "$INSTALLER_STATE_FILE")"
touch "$INSTALLER_STATE_FILE"

restore_installer_state() {
    local resource path

    while IFS=$'\t' read -r resource path; do
        [[ -n "$path" ]] || continue
        case "$resource" in
            mount) INSTALLER_MOUNTS+=("$path") ;;
            mapper) INSTALLER_MAPPERS+=("$path") ;;
        esac
    done < "$INSTALLER_STATE_FILE"
}

record_state() {
    printf '%s\t%s\n' "$1" "$2" >> "$INSTALLER_STATE_FILE"
}

partition_choice_device() {
    cut -f1 <<< "$1"
}

register_mount() {
    local mountpoint="$1"
    INSTALLER_MOUNTS+=("$mountpoint")
    record_state mount "$mountpoint"
}

register_mapper() {
    local mapper="$1"
    INSTALLER_MAPPERS+=("$mapper")
    record_state mapper "$mapper"
}

cleanup_target() {
    local mountpoint mapper remaining_mounts remaining_mappers default_mapper
    local -a cleanup_mounts=()

    if ((${#INSTALLER_MOUNTS[@]} == 0 && ${#INSTALLER_MAPPERS[@]} == 0)); then
        restore_installer_state
    fi
    default_mapper="${MAPPER_DEV##*/}"
    if [[ -n "$default_mapper" && ! " ${INSTALLER_MAPPERS[*]} " =~ [[:space:]]$default_mapper[[:space:]] ]]; then
        INSTALLER_MAPPERS+=("$default_mapper")
    fi

    while IFS= read -r mountpoint; do
        [[ -n "$mountpoint" ]] && cleanup_mounts+=("$mountpoint")
    done < <(findmnt -rn -o TARGET -R --target "$TARGET_MNT" 2>/dev/null | sort)
    cleanup_mounts+=("${INSTALLER_MOUNTS[@]}")

    for ((i = ${#cleanup_mounts[@]} - 1; i >= 0; i--)); do
        mountpoint="${cleanup_mounts[$i]}"
        if mountpoint -q "$mountpoint" 2>/dev/null; then
            debug_msg "Unmounting installer mount: $mountpoint"
            umount "$mountpoint" 2>/dev/null || warn_msg "Could not unmount $mountpoint"
        fi
    done

    for ((i = ${#INSTALLER_MAPPERS[@]} - 1; i >= 0; i--)); do
        mapper="${INSTALLER_MAPPERS[$i]}"
        if [[ -b "/dev/mapper/$mapper" ]]; then
            debug_msg "Closing installer mapper: $mapper"
            cryptsetup close "$mapper" 2>/dev/null || warn_msg "Could not close $mapper"
        fi
    done

    remaining_mounts=$(findmnt -rn -o TARGET -R --target "$TARGET_MNT" 2>/dev/null || true)
    remaining_mappers=""
    for mapper in "${INSTALLER_MAPPERS[@]}"; do
        if [[ -b "/dev/mapper/$mapper" ]]; then
            remaining_mappers+="$mapper\n"
        fi
    done
    if [[ -z "$remaining_mounts" && -z "$remaining_mappers" ]]; then
        rm -f "$INSTALLER_STATE_FILE"
    fi
}
