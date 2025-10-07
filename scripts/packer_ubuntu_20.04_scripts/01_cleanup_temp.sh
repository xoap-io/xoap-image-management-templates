#!/bin/bash
# Optimized temp and cache cleanup for Ubuntu 20.04

set -e

echo "[INFO] Starting temp and cache cleanup..."

# Clean apt cache
echo "[INFO] Cleaning apt cache..."
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove -y

# Clean systemd journal logs (if not needed)
echo "[INFO] Cleaning systemd journal logs..."
sudo journalctl --vacuum-time=7d || true

# Clean /tmp and /var/tmp
echo "[INFO] Cleaning /tmp and /var/tmp..."
sudo find /tmp -mindepth 1 -delete
sudo find /var/tmp -mindepth 1 -delete

# Clean user cache and thumbnails
echo "[INFO] Cleaning user cache and thumbnails..."
for user in $(ls /home); do
    sudo rm -rf /home/$user/.cache/*
    sudo rm -rf /home/$user/.thumbnails/*
done

# Clean log files
echo "[INFO] Cleaning log files..."
sudo find /var/log -type f -name "*.log" -delete
sudo find /var/log -type f -name "*.gz" -delete
sudo find /var/log -type f -name "*.1" -delete

# Clean crash reports
echo "[INFO] Cleaning crash reports..."
sudo rm -rf /var/crash/*

# Clean orphaned packages
echo "[INFO] Removing orphaned packages..."
sudo deborphan | xargs -r sudo apt-get -y remove --purge || true

echo "[INFO] Temp and cache cleanup completed."
