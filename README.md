# HiveOS GPU Stats Watchdog

This repository contains an installer and a rollback script for a HiveOS service that reboots a mining rig when GPU telemetry disappears during mining.

## What it monitors

The service waits 60 seconds after it starts, then checks every 10 seconds. It only acts while HiveOS indicates mining is active and the Hive miner process is running. It checks `/run/hive/gpu-stats.json` against the AMD GPU list in `/run/hive/gpu-detect.json`. Stats are considered unhealthy if the stats file is missing or more than 60 seconds old, if AMD GPU entries are missing, or if an AMD GPU temperature or power reading is invalid.

If stats remain unhealthy for 30 seconds, the service writes a persistent reboot marker and reboots once. The marker prevents another reboot for the same incident. It is cleared only after stats remain healthy for five minutes.

## Install

Run this on the HiveOS rig as root:

```bash
curl -fsSL https://raw.githubusercontent.com/playstorepantech/collectionofscripts/main/install-hive-gpu-stats-watchdog.sh | sudo bash
```

The installer saves a checkpoint under `/hive-config/checkpoints/`, installs and enables `hive-gpu-stats-watchdog.service`, and starts it.

## Roll back / disable

Run this on the rig as root:

```bash
curl -fsSL https://raw.githubusercontent.com/playstorepantech/collectionofscripts/main/rollback-hive-gpu-stats-watchdog.sh | sudo bash
```

This creates `/hive-config/disable-gpu-stats-watchdog`, then stops and disables the service. The disable flag remains in place so a later service start will not re-enable reboot behavior. To install again intentionally, remove that flag first, then rerun the installer.

## Check status and logs

```bash
systemctl status hive-gpu-stats-watchdog.service
journalctl -u hive-gpu-stats-watchdog.service -f
journalctl -t hive-gpu-stats-watchdog -n 50
```

The service script and rollback helper are installed in `/hive-config/`. Checkpoints from installation are kept in `/hive-config/checkpoints/`.
