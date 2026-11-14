#!/usr/bin/env bash
# Disable the HiveOS GPU stats watchdog and prevent it from rebooting the rig.
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
