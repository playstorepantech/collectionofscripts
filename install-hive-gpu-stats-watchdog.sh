#!/usr/bin/env bash
# Install a guarded HiveOS GPU-stats watchdog.
# Usage: sudo bash install-hive-gpu-stats-watchdog.sh
# Waits 60 seconds at service start, then monitors AMD GPU stats while mining.
# Reboots once after stats stay missing or invalid; the persistent guard prevents loops.
# Roll back with: sudo bash /hive-config/rollback-gpu-stats-watchdog.sh
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi
if [[ ! -d /hive-config || ! -d /run/hive || ! -d /sys/class/drm ]]; then
    echo "This installer requires a running HiveOS rig." >&2
    exit 1
fi
if [[ -e /hive-config/disable-gpu-stats-watchdog ]]; then
    echo "Watchdog disable file exists. Remove it intentionally before reinstalling." >&2
    exit 1
fi

stamp=$(date +%Y%m%d-%H%M%S)
checkpoint="/hive-config/checkpoints/gpu-stats-watchdog-installer-$stamp"
install -d -m 755 "$checkpoint"
for path in \
    /hive-config/gpu-stats-watchdog.sh \
    /hive-config/rollback-gpu-stats-watchdog.sh \
    /hive-config/hive-gpu-stats-watchdog.service \
    /etc/systemd/system/hive-gpu-stats-watchdog.service; do
    if [[ -e $path ]]; then
        cp -a "$path" "$checkpoint/$(basename "$path").before"
    fi
done

cat > /hive-config/gpu-stats-watchdog.sh <<'SCRIPT'
#!/usr/bin/env bash
set -u

STATS=/run/hive/gpu-stats.json
DETECT=/run/hive/gpu-detect.json
DISABLE=/hive-config/disable-gpu-stats-watchdog
REBOOT_MARKER=/hive-config/gpu-stats-watchdog.rebooted
CHECK_INTERVAL=5
STALE_AFTER=60
HEALTHY_TO_RESET=300
healthy_since=0

log() { logger -t hive-gpu-stats-watchdog "$*"; }

mining() {
    [[ -e /run/hive/MINER_RUN ]] && pgrep -f '^(/bin/)?bash /hive/bin/miner-run([[:space:]]|$)' >/dev/null
}

stats_healthy() {
    [[ -r $STATS && -r $DETECT ]] || return 1
    local now mtime age expected
    now=$(date +%s)
    mtime=$(stat -c %Y "$STATS" 2>/dev/null) || return 1
    age=$((now - mtime))
    ((age <= STALE_AFTER)) || return 1

    expected=$(jq '[.[] | select((.brand // "" | ascii_downcase) == "amd")] | length' "$DETECT" 2>/dev/null) || return 1
    ((expected > 0)) || return 1

    jq -e --argjson expected "$expected" '
        . as $s |
        (($s.brand | type) == "array") and
        (($s.temp | type) == "array") and
        (($s.power | type) == "array") and
        ([range(0; ($s.brand | length)) | select((($s.brand[.] // "") | ascii_downcase) == "amd")] as $ids |
            (($ids | length) == $expected) and
            all($ids[]; (($s.temp[.] | tonumber? // 0) > 0) and (($s.power[.] | tonumber?) != null))
        )
    ' "$STATS" >/dev/null 2>&1
}

log "Started; checking every ${CHECK_INTERVAL}s with immediate reboot on unhealthy GPU stats. Touch $DISABLE to disable."
while true; do
    if [[ -e $DISABLE ]]; then
        log "Disable file found; exiting without reboot."
        exit 0
    fi

    if ! mining; then
                healthy_since=0
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if stats_healthy; then
                if [[ -s $REBOOT_MARKER ]]; then
            ((healthy_since == 0)) && healthy_since=$(date +%s)
            if (( $(date +%s) - healthy_since >= HEALTHY_TO_RESET )); then
                : > "$REBOOT_MARKER"
                log "Stats healthy for 5 minutes; cleared the one-reboot guard."
            fi
        else
            healthy_since=0
        fi
    else
        healthy_since=0
        if [[ -s $REBOOT_MARKER ]]; then
            log "GPU stats are missing, stale, or incomplete, but reboot was already attempted for this incident; suppressing another reboot."
        else
            printf '%s\n' "$(date +%s)" > "$REBOOT_MARKER"
            sync
            log "GPU stats are missing, stale, or incomplete while miner is running; rebooting immediately."
            /usr/bin/systemctl reboot
            exit 0
        fi
    fi
    sleep "$CHECK_INTERVAL"
done
SCRIPT

cat > /hive-config/rollback-gpu-stats-watchdog.sh <<'SCRIPT'
#!/usr/bin/env bash
set -e
systemctl disable --now hive-gpu-stats-watchdog.service 2>/dev/null || true
: > /hive-config/disable-gpu-stats-watchdog
echo "GPU stats watchdog disabled. It will not reboot this rig."
SCRIPT

cat > /hive-config/hive-gpu-stats-watchdog.service <<'UNIT'
[Unit]
Description=Reboot once if HiveOS GPU stats disappear during mining
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash /hive-config/gpu-stats-watchdog.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

install -m 644 /hive-config/hive-gpu-stats-watchdog.service /etc/systemd/system/hive-gpu-stats-watchdog.service
chmod 755 /hive-config/gpu-stats-watchdog.sh /hive-config/rollback-gpu-stats-watchdog.sh
systemctl daemon-reload
systemctl enable hive-gpu-stats-watchdog.service
systemctl restart hive-gpu-stats-watchdog.service

echo "Installed watchdog. It checks GPU stats every 5s while mining and reboots immediately on an unhealthy check."
echo "Rollback: bash /hive-config/rollback-gpu-stats-watchdog.sh"
echo "Checkpoint: $checkpoint"
