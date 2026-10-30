#!/bin/bash
# pacstrap launcher: `pacstrap -K <mnt> <packages…>`.

if [[ ${_SOURCED_pkg_pacstrap:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_pkg_pacstrap="loaded"

module::provide pkg.pacstrap pacstrap::run

# pacstrap::run <mnt> <packages[@]>
pacstrap::run() {
    local mnt="$1"
    shift
    (($# > 0)) || {
        warn_msg "pacstrap::run: empty package list"
        return 0
    }
    debug_msg "Installing $# packages via pacstrap into $mnt"
    ui::spin "Installing base system..." -- pacstrap -K "$mnt" "$@"
}
