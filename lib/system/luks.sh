#!/bin/bash

# LUKS2 APIs: format/open/uuid/header-backup.

if [[ ${_SOURCED_system_luks:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_system_luks="loaded"

module::provide system.luks luks::format luks::open luks::uuid luks::header_backup

# luks::format <dev> <passfile>
#   LUKS2 container format + luksDump metadata verification
luks::format() {
    local dev="$1" passfile="$2"
    if ! ui::spin "Formatting LUKS2 container on $dev..." -- \
        cryptsetup luksFormat --type luks2 --batch-mode --force-password "$dev" -d "$passfile"; then
        error_msg "LUKS formatting failed"
        return 1
    fi
    if ! ui::spin "Verifying LUKS metadata on $dev..." -- cryptsetup luksDump "$dev"; then
        error_msg "LUKS metadata verification failed"
        return 1
    fi
    return 0
}

# luks::open <dev> <name> <passfile>
luks::open() {
    local dev="$1" name="$2" passfile="$3"
    exec_cmd cryptsetup open "$dev" "$name" -d "$passfile" || return 1
    register_mapper "$name"
    return 0
}

# luks::uuid <out_var> <dev>
luks::uuid() {
    local -n out_uuid="$1"
    local src_dev="$2"
    local probe_uuid

    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        out_uuid="00000000-0000-0000-0000-000000000000"
        debug_msg "DRY-RUN: canned LUKS UUID (no container was formatted)"
        return 0
    fi
    if ! probe_uuid=$(cryptsetup luksUUID "$src_dev"); then
        error_msg "Could not read LUKS UUID from: $src_dev"
        return 1
    fi
    out_uuid="$probe_uuid"
    return 0
}

# luks::header_backup <out_file> <dev> <dir>
#   Writes <dir>/<uuid>.luks-header (0600) and sets out_file
luks::header_backup() {
    local -n out_file="$1"
    local dev="$2" dir="$3"
    local backup_uuid backup

    luks::uuid backup_uuid "$dev" || return 1
    if [[ ${FR0ST_DRYRUN:-0} != "1" ]]; then
        [[ -d "$dir" ]] || {
            error_msg "LUKS header backup directory does not exist: $dir"
            return 1
        }
    fi
    backup="$dir/${backup_uuid}.luks-header"
    exec_cmd cryptsetup luksHeaderBackup "$dev" --header-backup-file "$backup" || return 1
    if [[ ${FR0ST_DRYRUN:-0} == "1" ]]; then
        debug_msg "DRY-RUN: header backup not executed; skipping the size guard"
        out_file="$backup"
        return 0
    fi
    [[ -s "$backup" ]] || {
        error_msg "LUKS header backup was not created or is empty"
        return 1
    }
    chmod 600 "$backup"
    out_file="$backup"
    return 0
}

return 0
