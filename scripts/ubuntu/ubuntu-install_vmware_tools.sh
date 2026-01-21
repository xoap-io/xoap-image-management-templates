#!/bin/bash
#===================================================================================
# Script: install_vmware_tools_ubuntu.sh
# Description: Install VMware Tools/open-vm-tools for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./install_vmware_tools_ubuntu.sh
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

log_info "Starting VMware Tools installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0

# Detect virtualization platform
log_info "Detecting virtualization platform..."
VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "none")

log_info "Detected platform: $VIRT_PLATFORM"

if [[ "$VIRT_PLATFORM" != "vmware" ]]; then
    log_warn "Not running on VMware platform"
    log_info "Continuing with installation anyway..."
fi

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Install open-vm-tools
log_info "Installing open-vm-tools..."

PACKAGES="open-vm-tools"

# Add desktop packages if GUI is present
if [[ -n "${DISPLAY:-}" ]] || dpkg -l | grep -q "ubuntu-desktop\|xubuntu-desktop\|kubuntu-desktop"; then
    log_info "Desktop environment detected, including desktop tools..."
    PACKAGES="$PACKAGES open-vm-tools-desktop"
fi

if DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES; then
    log_info "✓ open-vm-tools installed successfully"
    ((PACKAGES_INSTALLED++))
else
    log_error "Failed to install open-vm-tools"
    exit 1
fi

# Get installed version
if dpkg -l | grep -q "^ii.*open-vm-tools"; then
    TOOLS_VERSION=$(dpkg -l open-vm-tools | grep '^ii' | awk '{print $3}')
    log_info "Installed version: $TOOLS_VERSION"
fi

# Enable and start open-vm-tools service
log_info "Enabling open-vm-tools service..."

systemctl enable open-vm-tools
systemctl start open-vm-tools

# Wait for service to start
sleep 2

if systemctl is-active --quiet open-vm-tools; then
    log_info "✓ open-vm-tools service is running"
else
    log_error "✗ open-vm-tools service failed to start"
    systemctl status open-vm-tools --no-pager
    exit 1
fi

# Enable vgauth service if available
if systemctl list-unit-files | grep -q "vgauth.service"; then
    log_info "Enabling vgauth service..."
    systemctl enable vgauth
    systemctl start vgauth
    
    if systemctl is-active --quiet vgauth; then
        log_info "✓ vgauth service is running"
    else
        log_warn "✗ vgauth service failed to start"
    fi
fi

# Check for vmhgfs-fuse (shared folders)
if command -v vmhgfs-fuse &>/dev/null; then
    log_info "✓ Shared folders support available"
    
    # Create mount point
    mkdir -p /mnt/hgfs
    
    # Add to fstab if not present
    if ! grep -q "vmhgfs-fuse" /etc/fstab; then
        echo ".host:/ /mnt/hgfs fuse.vmhgfs-fuse allow_other,defaults 0 0" >> /etc/fstab
        log_info "✓ Shared folders configured in /etc/fstab"
        ((PACKAGES_INSTALLED++))
    fi
else
    log_info "Shared folders support not available"
fi

# Test VMware Tools functionality
log_info "Testing VMware Tools functionality..."

if command -v vmware-toolbox-cmd &>/dev/null; then
    log_info "VMware Tools information:"
    
    TOOLS_VERSION=$(vmware-toolbox-cmd -v 2>/dev/null || echo "unknown")
    log_info "  Version: $TOOLS_VERSION"
    
    VM_STATUS=$(vmware-toolbox-cmd stat sessionid 2>/dev/null || echo "unknown")
    log_info "  Session ID: $VM_STATUS"
else
    log_warn "vmware-toolbox-cmd not available"
fi

# Check time synchronization
log_info "Checking time synchronization..."

if vmware-toolbox-cmd timesync status &>/dev/null; then
    TIMESYNC_STATUS=$(vmware-toolbox-cmd timesync status)
    log_info "  Time sync status: $TIMESYNC_STATUS"
    
    if [[ "$TIMESYNC_STATUS" == *"Disabled"* ]]; then
        log_info "  Enabling time synchronization..."
        vmware-toolbox-cmd timesync enable
        log_info "  ✓ Time sync enabled"
    fi
else
    log_info "  Time sync control not available"
fi

# Display service status
log_info "Service status:"
for service in open-vm-tools vgauth; do
    if systemctl list-unit-files | grep -q "${service}.service"; then
        STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        ENABLED=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        log_info "  $service: $STATUS ($ENABLED)"
    fi
done

# Check for VMware kernel modules
log_info "Checking VMware kernel modules..."

VMWARE_MODULES=("vmw_balloon" "vmw_vmci" "vmw_vsock_vmci_transport" "vmwgfx" "vmxnet3")

for module in "${VMWARE_MODULES[@]}"; do
    if lsmod | grep -q "^$module"; then
        log_info "  ✓ $module loaded"
    else
        log_info "  - $module not loaded"
    fi
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "VMware Tools Installation Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Package version: $(dpkg -l open-vm-tools 2>/dev/null | grep '^ii' | awk '{print $3}' || echo 'unknown')"
log_info "Service status: $(systemctl is-active open-vm-tools 2>/dev/null || echo 'inactive')"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "VMware Tools installation completed!"
log_info ""
log_info "Useful commands:"
log_info "  - Version: vmware-toolbox-cmd -v"
log_info "  - Status: systemctl status open-vm-tools"
log_info "  - Time sync: vmware-toolbox-cmd timesync status"
log_info "  - Mount shared folders: mount -t fuse.vmhgfs-fuse .host:/ /mnt/hgfs"