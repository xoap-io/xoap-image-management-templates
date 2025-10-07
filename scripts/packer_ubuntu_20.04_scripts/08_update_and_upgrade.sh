#!/bin/bash
# Optimized system update and upgrade for Ubuntu 20.04

set -e

log() {
    echo "[UPDATE] $1"
}

log "Updating package lists..."
sudo apt-get update

log "Upgrading installed packages..."
sudo apt-get upgrade -y

log "Performing distribution upgrade..."
sudo apt-get dist-upgrade -y

log "Removing unused packages..."
sudo apt-get autoremove --purge -y

log "Cleaning up package cache..."
sudo apt-get clean

log "System update and upgrade complete."
