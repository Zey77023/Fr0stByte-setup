#!/bin/bash

# stage 17 — fonts: optional fonts installation and configuration with cache refresh

STAGE_ID="17-fonts"
STAGE_KIND="mutating"
STAGE_DESC="Install the opinionated font set and fontconfig preferences"
STAGE_APIS=(
    core.state core.ui
    pkg.lists pkg.pacman
    config.files_apply system.chroot
)

run_stage() {
    debug_msg "Starting font installation and configuration stage"
    status_msg "Installing fonts to target system..."

    if ! ui::confirm fonts_install \
        "Install fonts and configure font settings?" "no"; then
        status_msg "Font installation skipped"
        success_msg "Font installation and configuration complete"
        return 0
    fi

    status_msg "Installing fonts"
    local st_font_list="${FR0ST_FONT_PKGS:-$INSTALLER_ROOT/lib/pkg/lists/font-packages}"
    local -a st_font_pkgs=()
    lists::load "$st_font_list" st_font_pkgs || return 1
    pacman::target "$TARGET_MNT" -S --needed --noconfirm \
        "${st_font_pkgs[@]}" || return 1
    success_msg "Fonts installed"

    status_msg "Configuring font settings..."
    files_apply::apply "$TARGET_MNT" --only etc/fonts/local.conf || return 1
    success_msg "Font settings configured"

    status_msg "Regenerating font cache..."
    ui::spin "Regenerating font cache..." \
        -- chroot_exec "$TARGET_MNT" -- fc-cache -fv || return 1
    success_msg "Font cache regenerated"

    state_set "fonts/installed" "done"
    success_msg "Font installation and configuration complete"
    return 0
}
