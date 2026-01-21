#!/bin/bash
#===================================================================================
# Script: install_vmware_tools_rhel.sh
# Description: Install VMware Tools (open-vm-tools) for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./install_vmware_tools_rhel.sh
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

log_info "Starting VMware Tools installation..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

# Check if running in VMware
log_info "Detecting virtualization platform..."
VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "unknown")

log_info "Detected platform: $VIRT_PLATFORM"

if [[ "$VIRT_PLATFORM" != "vmware" ]]; then
    log_warn "Not running on VMware platform"
    log_info "Continuing with installation anyway..."
fi

# Install open-vm-tools
log_info "Installing open-vm-tools packages..."

VMTOOLS_PACKAGES=(
    "open-vm-tools"
    "open-vm-tools-desktop"
)

for package in "${VMTOOLS_PACKAGES[@]}"; do
    if rpm -q "$package" &>/dev/null; then
        log_info "Package already installed: $package"
        PACKAGES_INSTALLED=$((PACKAGES_INSTALLED + 1))
    else
        log_info "Installing: $package"
        
        if $PKG_MGR install -y "$package" 2>&1 | tee -a /tmp/vmware-tools-install.log; then
            PACKAGES_INSTALLED=$((PACKAGES_INSTALLED + 1))
            log_info "Successfully installed: $package"
        else
            log_warn "Failed to install: $package (may not be available)"
        fi
    fi
done

# Enable and start vmtoolsd service
log_info "Enabling and starting vmtoolsd service..."

if systemctl list-unit-files | grep -q "vmtoolsd"; then
    systemctl enable vmtoolsd
    systemctl start vmtoolsd
    
    # Check service status
    if systemctl is-active --quiet vmtoolsd; then
        log_info "vmtoolsd service is running"
    else
        log_warn "vmtoolsd service failed to start"
    fi
else
    log_warn "vmtoolsd service not found"
fi

# Verify installation
log_info "Verifying VMware Tools installation..."

if command -v vmware-toolbox-cmd &>/dev/null; then
    VMTOOLS_VERSION=$(vmware-toolbox-cmd -v 2>/dev/null || echo "unknown")
    log_info "VMware Tools version: $VMTOOLS_VERSION"
    
    # Display VMware Tools status
    log_info "VMware Tools status:"
    vmware-toolbox-cmd stat raw text session 2>/dev/null | while IFS= read -r line; do
        log_info "  $line"
    done
else
    log_warn "vmware-toolbox-cmd not found"
fi

# Check if HGFS (shared folders) module is loaded
if lsmod | grep -q "vmhgfs"; then
    log_info "HGFS module is loaded (shared folders supported)"
else
    log_info "HGFS module not loaded (shared folders not available)"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "VMware Tools Installation Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Service status: $(systemctl is-active vmtoolsd 2>/dev/null || echo 'not running')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "VMware Tools installation completed!"