#!/bin/bash

# Detect CPU Vendor
VENDOR=$(grep -m 1 "vendor_id" /proc/cpuinfo | awk '{print $3}')

case "$VENDOR" in
    GenuineIntel) echo "intel"   ;;
    AuthenticAMD) echo "amd"     ;;
    *)            echo "unknown" ;;
esac
