#!/bin/bash

debug_msg "Starting optional performance profile stage"

status_msg "Optional performance tweaks"

PERFORMANCE_DIR="$TARGET_MNT/etc/fr0stbyte"
PERFORMANCE_CONF="$PERFORMANCE_DIR/performance.conf"
SYSCTL_CONF="$TARGET_MNT/etc/sysctl.d/60-fr0stbyte-performance.conf"
mkdir -p "$PERFORMANCE_DIR" "$TARGET_MNT/etc/sysctl.d"

write_reset_script() {
    local reset_script="$TARGET_MNT/usr/local/sbin/fr0stbyte-performance-reset"

    mkdir -p "$(dirname "$reset_script")"
    cat >"$reset_script" <<'EOF'
#!/bin/bash

set -eu

rm -f /etc/fr0stbyte/performance.conf
rm -f /etc/sysctl.d/60-fr0stbyte-performance.conf
sysctl --system
printf 'Fr0stByte performance profile reset.\n'
EOF
    chmod 755 "$reset_script"
}

# Cleanup
rm -f "$PERFORMANCE_CONF" "$SYSCTL_CONF"

# ZRAM tweaks
if gum confirm "Set vm.swappiness=100 for zram?" --default=no; then
    printf 'PROFILE_SWAPPINESS="enabled"\n' >>"$PERFORMANCE_CONF"
    printf '%s\n' '# Fr0stByte opt-in swappiness tweak.' 'vm.swappiness = 100' >>"$SYSCTL_CONF"
    write_reset_script
    success_msg "Enabled vm.swappiness=100"
else
    status_msg "vm.swappiness tweak declined"
fi

if gum confirm "Set vm.page-cluster=0 for zram?" --default=no; then
    printf 'PROFILE_PAGE_CLUSTER="enabled"\n' >>"$PERFORMANCE_CONF"
    printf '%s\n' '# Fr0stByte opt-in page-cluster tweak.' 'vm.page-cluster = 0' >>"$SYSCTL_CONF"
    write_reset_script
    success_msg "Enabled vm.page-cluster=0"
else
    status_msg "vm.page-cluster tweak declined"
fi

# Network tweaks
BBR_AVAILABLE=$(cat /proc/sys/net/ipv4/tcp_allowed_congestion_control 2>/dev/null || true)
if [[ " $BBR_AVAILABLE " == *" bbr "* ]]; then
    if gum confirm "Enable the BBR network congestion-control tweak?" --default=no; then
        [[ -f "$PERFORMANCE_CONF" ]] || : >"$PERFORMANCE_CONF"
        printf 'PROFILE_NETWORK_BBR="enabled"\n' >>"$PERFORMANCE_CONF"
        [[ -f "$SYSCTL_CONF" ]] || : >"$SYSCTL_CONF"
        cat >>"$SYSCTL_CONF" <<'EOF'
# Fr0stByte opt-in BBR profile.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        write_reset_script
        success_msg "Enabled the BBR congestion-control profile"
    else
        status_msg "BBR network tweak declined"
    fi
else
    status_msg "BBR is unavailable in the running kernel; skipping that tweak"
fi

status_msg "Performance tweaks complete"
