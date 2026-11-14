#!/usr/bin/env bash
# Disable the HiveOS GPU stats watchdog and prevent it from rebooting the rig.
# Usage on a HiveOS rig: sudo bash rollback-hive-gpu-stats-watchdog.sh
# Creates a persistent disable flag, then stops and disables the systemd service.
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

if [[ ! -d /hive-config ]]; then
    echo "This rollback script requires a HiveOS rig." >&2
    exit 1
fi

# Set the persistent kill switch before stopping the service.
: > /hive-config/disable-gpu-stats-watchdog
systemctl disable --now hive-gpu-stats-watchdog.service
echo "GPU stats watchdog stopped and disabled. The persistent disable flag is /hive-config/disable-gpu-stats-watchdog."
