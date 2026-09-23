#!/bin/bash

debug_msg "Starting base system installation stage"

require_network

# Prepare packages to install
load_pkglist "$INSTALLER_ROOT/pacstrap-packages"
printf '%s\n' "${PKGS[@]}" | grep -Fxq linux-zen || {
	error_msg "linux-zen is required; kernel selection is not configurable in this installer"
	exit 1
}
add_cpu_microcode
add_hardware_packages

# Bootstrap the base system with the prepared package list
status_msg "Installing base system..."
debug_msg "Installing ${#PKGS[@]} packages via pacstrap"
pacstrap -K "$TARGET_MNT" "${PKGS[@]}"

success_msg "Base system installed"
