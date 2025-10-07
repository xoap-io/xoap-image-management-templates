#!/bin/bash
# Optimized disabling of unnecessary services for Ubuntu 20.04

set -e

# List of unnecessary services for minimal/server images
SERVICES=(cups avahi-daemon bluetooth ModemManager rpcbind lxd snapd ufw apport)

echo "[INFO] Disabling unnecessary services..."

for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^$svc"; then
    echo "[INFO] Disabling and stopping: $svc"
    sudo systemctl disable $svc 2>/dev/null || echo "[WARN] Could not disable $svc"
    sudo systemctl stop $svc 2>/dev/null || echo "[WARN] Could not stop $svc"
  else
    echo "[INFO] Service not found: $svc"
  fi
  # Mask the service to prevent accidental start
  sudo systemctl mask $svc 2>/dev/null || true
  # Remove the package if possible
  if dpkg -l | grep -q "^ii  $svc "; then
    echo "[INFO] Removing package: $svc"
    sudo apt-get purge -y $svc || echo "[WARN] Could not purge $svc"
  fi

done

echo "[INFO] Unnecessary service disable completed."
