#!/bin/bash

# stage 06 — pacstrap: build the target package list (base + microcode + NVIDIA) and pacstrap the
# system with the built package list

STAGE_ID="06-pacstrap"
STAGE_KIND="mutating"
STAGE_DESC="pacstrap -K the base system (incl. negotiated microcode/driver packages) into the target"
STAGE_APIS=(pkg.lists pkg.pacstrap system.detect)

run_stage() {
    debug_msg "Starting base system installation stage"

    local pkg_list="${FR0ST_PACSTRAP_PKGS:-$INSTALLER_ROOT/lib/pkg/lists/pacstrap-packages}"
    local -a st_pkgs=()
    lists::load "$pkg_list" st_pkgs || return 1

    local st_microcode
    detect::microcode_pkg st_microcode || return 1
    st_pkgs+=("$st_microcode")

    local -a st_gpu_pkgs=()
    detect::gpu_pkgs st_gpu_pkgs || return 1
    if ((${#st_gpu_pkgs[@]} > 0)); then
        st_pkgs+=("${st_gpu_pkgs[@]}")
    fi

    pacstrap::run "$TARGET_MNT" "${st_pkgs[@]}" || return 1

    success_msg "Base system installed"
    return 0
}
