#!/bin/bash

# stage 01 — bootstrap: sync host package databases and install the
# installer's own script dependencies.

STAGE_ID="01-bootstrap"
STAGE_KIND="mutating"
STAGE_DESC="pacman repo sync + host install of script-dependencies"
STAGE_APIS=(core.state pkg.pacman pkg.lists)

run_stage() {
    local deps_file="${FR0ST_SCRIPT_DEPS:-$INSTALLER_ROOT/lib/pkg/lists/script-dependencies}"

    pacman::sync || return 1

    local -a st_deps=()
    lists::load "$deps_file" st_deps || return 1
    pacman::host_install "${st_deps[@]}" || return 1

    success_msg "Bootstrap complete"
    return 0
}
