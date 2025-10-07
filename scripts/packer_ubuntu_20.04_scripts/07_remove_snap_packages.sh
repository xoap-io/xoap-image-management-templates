#!/bin/bash
# Optimized removal of snap packages for Ubuntu 20.04

set -e

log() {
    echo "[SNAP] $1"
}

log "Stopping snapd service..."
sudo systemctl stop snapd || true
sudo systemctl disable snapd || true

log "Removing all installed snap packages..."
if command -v snap &>/dev/null; then
    for pkg in $(snap list | awk 'NR>1 {print $1}'); do
        sudo snap remove "$pkg" || true
    done
fi

log "Purging snapd and related packages..."
sudo apt-get purge snapd -y
sudo apt-get autoremove --purge -y

log "Removing snap directories..."
sudo rm -rf ~/snap /snap /var/snap /var/lib/snapd /var/cache/snapd

log "Snap removal complete."
