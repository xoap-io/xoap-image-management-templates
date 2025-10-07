#!/bin/bash
# Optimized UFW firewall hardening for Ubuntu 20.04

set -e

log() {
    echo "[UFW] $1"
}

log "Resetting UFW to default..."
sudo ufw --force reset

log "Setting default policies..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed

log "Allowing essential services..."
sudo ufw allow OpenSSH
# Uncomment and adjust the following lines as needed:
# sudo ufw allow 80/tcp    # HTTP
# sudo ufw allow 443/tcp   # HTTPS
# sudo ufw allow from 192.168.0.0/16 to any port 22 proto tcp  # Example: restrict SSH to local network

log "Enabling logging..."
sudo ufw logging on

log "Enabling UFW firewall..."
sudo ufw --force enable

log "UFW firewall hardening complete."
