#!/bin/bash
#===================================================================================
# Script: install_nutanix_tools_ubuntu.sh
# Description: Install Nutanix Guest Tools for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./install_nutanix_tools_ubuntu.sh
#===================================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# Error handler
error_exit() {
    log_error "Script failed at line $1"
    exit 1
}

trap 'error_exit $LINENO' ERR

# Root check
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting Nutanix Guest Tools installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0

# Detect virtualization platform
log_info "Detecting virtualization platform..."
VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "none")

log_info "Detected platform: $VIRT_PLATFORM"

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# NGT is typically installed via ISO mount
# Check for mounted NGT ISO
NGT_MOUNT="/media/NUTANIX_TOOLS"

if [[ ! -d "$NGT_MOUNT" ]]; then
    # Try to find and mount NGT ISO
    for device in /dev/sr* /dev/cdrom; do
        if [[ -b "$device" ]]; then
            mkdir -p "$NGT_MOUNT"
            if mount -o ro "$device" "$NGT_MOUNT" 2>/dev/null; then
                log_info "✓ Mounted Nutanix Tools ISO from $device"
                break
            fi
        fi
    done
fi

if [[ -d "$NGT_MOUNT" ]] && [[ -f "$NGT_MOUNT/installer/linux/install_ngt.py" ]]; then
    log_info "Installing Nutanix Guest Tools..."
    
    cd "$NGT_MOUNT/installer/linux"
    
    if python3 install_ngt.py 2>&1 | tee /tmp/ngt-install.log; then
        log_info "✓ Nutanix Guest Tools installed"
        ((PACKAGES_INSTALLED++))
    else
        log_error "Failed to install Nutanix Guest Tools"
        cat /tmp/ngt-install.log
        exit 1
    fi
else
    log_warn "Nutanix Guest Tools ISO not found or not mounted"
    log_info "Installing qemu-guest-agent as alternative..."
    
    if DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent; then
        log_info "✓ qemu-guest-agent installed as alternative"
        ((PACKAGES_INSTALLED++))
    else
        log_error "Failed to install qemu-guest-agent"
        exit 1
    fi
fi

# Check for ngt_guest_agent service
if systemctl list-unit-files | grep -q "ngt_guest_agent"; then
    log_info "Enabling Nutanix Guest Agent..."
    
    systemctl enable ngt_guest_agent
    systemctl start ngt_guest_agent
    
    if systemctl is-active --quiet ngt_guest_agent; then
        log_info "✓ Nutanix Guest Agent is running"
    else
        log_warn "Nutanix Guest Agent failed to start"
    fi
else
    log_info "Using qemu-guest-agent for AHV compatibility"
    
    if systemctl list-unit-files | grep -q "qemu-guest-agent"; then
        systemctl enable qemu-guest-agent
        systemctl start qemu-guest-agent
        
        if systemctl is-active --quiet qemu-guest-agent; then
            log_info "✓ qemu-guest-agent is running"
        fi
    fi
fi

# Unmount NGT ISO if we mounted it
if mountpoint -q "$NGT_MOUNT" 2>/dev/null; then
    umount "$NGT_MOUNT"
    rmdir "$NGT_MOUNT" 2>/dev/null || true
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Nutanix Guest Tools Installation Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Service status: $(systemctl is-active ngt_guest_agent qemu-guest-agent 2>/dev/null | head -n1 || echo 'inactive')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Nutanix Guest Tools installation completed!"