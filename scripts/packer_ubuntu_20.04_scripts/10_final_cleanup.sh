#!/bin/bash
# Optimized final cleanup for Packer image finalization (Ubuntu 20.04)

set -e

log() {
    echo "[CLEANUP] $1"
}

log "Removing SSH host keys..."
sudo find /etc/ssh -type f -name '*_key' -exec shred -u {} +
sudo find /etc/ssh -type f -name '*_key.pub' -exec shred -u {} +

log "Removing shell histories..."
sudo rm -f /root/.bash_history
sudo rm -f /root/.zsh_history
sudo rm -f /home/*/.bash_history
sudo rm -f /home/*/.zsh_history

log "Clearing current shell history..."
history -c || true

log "Removing machine-id and cloud-init data..."
sudo rm -f /etc/machine-id
sudo rm -rf /var/lib/cloud/instances
sudo rm -rf /var/log/cloud-init*

log "Removing installer logs..."
sudo rm -rf /var/log/installer

log "Final cleanup complete."
