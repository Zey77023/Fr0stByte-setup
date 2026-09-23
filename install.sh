#!/bin/bash

# Exit on error, unset variable, or error in pipeline
set -euEo pipefail

# Variable abstractions for installer dependency paths
INSTALLER_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
INSTALLER_UTILS="$INSTALLER_ROOT/util"
INSTALLER_LIB="$INSTALLER_ROOT/lib"
INSTALLER_STAGES="$INSTALLER_ROOT/install"

# Mount point for target system
TARGET_MNT="/mnt"

# Log file setup
LOG_FILE="$INSTALLER_ROOT/install.log"
: >"$LOG_FILE"

# Library file sourcing
source "$INSTALLER_LIB/logging.sh"
source "$INSTALLER_LIB/checks.sh"
source "$INSTALLER_LIB/packages.sh"
source "$INSTALLER_LIB/input.sh"
source "$INSTALLER_LIB/system.sh"
source "$INSTALLER_LIB/state.sh"
source "$INSTALLER_LIB/fstab.sh"

# TRAP
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error_msg "Installation failed at stage: ${LAST_COMMAND:-unknown}"
        error_msg "Exit code: $exit_code"
        cleanup_target
    fi
}
trap 'LAST_COMMAND=$BASH_COMMAND; cleanup' ERR
trap 'cleanup_target; exit 130' INT
trap 'cleanup_target; exit 143' TERM
trap 'cleanup_target; exit 129' HUP

# Display installer banner
cat << 'EOF' | tee -a "$LOG_FILE"
    ______     ____       __  ____        __     
   / ____/____/ __ \_____/ /_/ __ )__  __/ /____ 
  / /_  / ___/ / / / ___/ __/ __  / / / / __/ _ \
 / __/ / /  / /_/ (__  ) /_/ /_/ / /_/ / /_/  __/
/_/   /_/   \____/____/\__/_____/\__, /\__/\___/ 
                                /____/           
EOF

debug_msg "Installer root anchored at: $INSTALLER_ROOT"
debug_msg "Logging to: $LOG_FILE"

# Cleanup target before starting installation
cleanup_target

# Go through all setup stages
for stage in "$INSTALLER_STAGES"/*.sh; do
    debug_msg "Executing stage: $stage"
    source "$stage"
done

success_msg "Installation finished."
