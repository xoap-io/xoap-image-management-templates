#!/bin/bash
# Optimized removal of unused packages for Ubuntu 20.04

set -e

echo "[INFO] Removing unused packages..."

# Remove orphaned packages
sudo apt-get autoremove -y
sudo apt-get autoclean

# Remove orphaned libraries (deborphan)
if command -v deborphan >/dev/null 2>&1; then
    echo "[INFO] Removing orphaned libraries..."
    sudo deborphan | xargs -r sudo apt-get -y remove --purge || true
else
    echo "[INFO] deborphan not found, skipping orphaned library removal."
fi

# Remove residual config files
echo "[INFO] Removing residual config files..."
sudo dpkg -l | awk '/^rc/ {print $2}' | xargs -r sudo apt-get purge -y || true

echo "[INFO] Unused package removal completed."
