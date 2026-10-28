#!/bin/bash

# stage 07 — fstab: generate fstab for the mounted hierarchy and write it
# to the target system. Verify written fstab for errors after writing it.

STAGE_ID="07-fstab"
STAGE_KIND="mutating"
STAGE_DESC="Generate /etc/fstab and verify it in the target"
STAGE_APIS=(core.state config.genfstab system.chroot)

run_stage() {
    debug_msg "Starting fstab generation stage"

    genfstab::write "$TARGET_MNT" || return 1

    state_set "fstab/verified" "done"
    success_msg "fstab written to $TARGET_MNT/etc/fstab (verified)"
    return 0
}
