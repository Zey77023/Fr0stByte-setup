#!/bin/bash

debug_msg "Starting bootstrap stage"

# Dependency check
require_paths "$INSTALLER_ROOT/script-dependencies"
require_network

# Sync repos
status_msg "Updating package databases..."
pacman -Sy --noconfirm

# Dependency installation
install_packages_from_list "$INSTALLER_ROOT/script-dependencies"

success_msg "Bootstrap complete"
