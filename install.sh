#!/bin/bash

# ! ------ Begin Refactoring Notes ------

# TODO: Separate logic into a directory called APIs and focus
# TODO: on making this script call those APIs for what needs to be done.
# TODO: APIs should also not depend on sourced variables directly, but the
# TODO: variables should be passed to the APIs as arguments

# TODO: Add checkpoint tracking for installation stages
# TODO: So, if the installer fails at any stage, it can
# TODO: ask the user if they want to resume installation
# TODO: from the last successful stage and start from there

# TODO: Separate validation into a directory called validation
# TODO: so validation logic has to be called by the main script
# TODO: before any API is called. This will shift APIs focus to
# TODO: only performing their required actions and not worry about
# TODO: receiving invalid inputs or wrong states

# TODO: The APIs directory can be merged into the lib directory

# TODO: Each installer stage should only import the APIs it needs to perform
# TODO: it's actions. All APIs won't be available to all stages like it is now.

# TODO: Instead of providing users a choice, be opinionated and limit how often
# TODO: the user has to interact with the installer

# TODO: Setup command tracing into a separate log file for debugging.
# TODO: Refer to "Trace idea" file in the root of project for details.
# TODO: Also refer https://stackoverflow.com/questions/685435/trace-of-executed-programs-called-by-a-bash-script

# TODO: Make a testing framework that will allow for any script to be run
# TODO: individually with logging in separate folder with all relevant
# TODO: information

# TODO: Add a new function in packages.sh which can handle installing packages in chroot
# TODO: as the current implementation of install_packages() only works for the host system. This leads to
# TODO: failure in installing font packages from the fonts.sh file

# TODO: Make sure all long running tasks display a gum spinner, for example when installing packages, formatting disk, etc.
# TODO: This will show the user that something is infact happening and there's no need to panic.

# ! ------ End Refactoring Notes ------

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
cat <<'EOF' | tee -a "$LOG_FILE"
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
