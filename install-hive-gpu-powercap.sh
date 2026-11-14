#!/usr/bin/env bash
# Install a boot service that keeps AMD GPU power caps aligned with HiveOS PL.
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

if [[ ! -d /hive-config || ! -d /sys/class/drm ]]; then
    echo "This installer requires a HiveOS rig with /hive-config and DRM sysfs." >&2
    exit 1
fi

cat > /hive-config/apply-gpu-powerlimit.sh <<'SCRIPT'
#!/usr/bin/env bash
# Keep each AMD GPU power1_cap aligned with the HiveOS PL profile.
while true; do
    PL=
    if [[ -r /hive-config/amd-oc.conf ]]; then
        source /hive-config/amd-oc.conf
    fi
    read -r -a limits <<< "${PL:-}"

    if ((${#limits[@]})); then
        gpu=0
        for cap in /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap; do
            [[ -r $cap && -w $cap ]] || continue
            limit=${limits[gpu]:-${limits[-1]}}
            ((gpu++))
            [[ $limit =~ ^[0-9]+$ ]] || continue
            target=$((limit * 1000000))
            current=$(<"$cap")
            if [[ $current != "$target" ]]; then
                printf '%s\n' "$target" > "$cap" && logger -t hive-gpu-powerlimit "Applied ${limit}W to $cap (was ${current} microwatts)"
            fi
        done
    fi
    sleep 1
done
SCRIPT

cat > /etc/systemd/system/hive-gpu-powerlimit.service <<'UNIT'
[Unit]
Description=Keep AMD GPU power caps aligned with HiveOS overclock profile
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash /hive-config/apply-gpu-powerlimit.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable hive-gpu-powerlimit.service
systemctl restart hive-gpu-powerlimit.service

echo "Installed and started hive-gpu-powerlimit.service (polling every 1 second)."
