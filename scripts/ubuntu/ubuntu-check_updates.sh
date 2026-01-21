#!/bin/bash
#===================================================================================
# Script: ubuntu-check_updates.sh
# Description: Check for available updates on Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./ubuntu-check_updates.sh
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

log_info "Checking for available updates on Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)

# Update package lists
log_info "Updating package lists..."

apt-get update -qq 2>&1 | tee /tmp/apt_update_check.log >/dev/null

if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    log_info "✓ Package lists updated"
else
    log_error "Failed to update package lists"
    exit 1
fi

# Count upgradable packages
log_info "Analyzing available updates..."

UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l || echo "0")

log_info "Total upgradable packages: $UPGRADABLE"

if [[ $UPGRADABLE -gt 0 ]]; then
    log_warn "⚠ $UPGRADABLE package(s) available for upgrade"
    
    # List upgradable packages
    log_info ""
    log_info "Available package updates:"
    log_info "=============================================="
    
    apt list --upgradable 2>/dev/null | grep -v "^Listing" | while IFS= read -r line; do
        log_info "  $line"
    done
else
    log_info "✓ System is up to date"
fi

# Check for security updates
log_info ""
log_info "Checking for security updates..."

SECURITY_UPDATES=0

if command -v unattended-upgrade &>/dev/null; then
    # Use unattended-upgrades to check security updates
    if unattended-upgrade --dry-run --debug 2>&1 | grep -q "Checking"; then
        SECURITY_UPDATES=$(unattended-upgrade --dry-run 2>&1 | grep -c "Checking:" || echo "0")
    fi
fi

if [[ $SECURITY_UPDATES -gt 0 ]]; then
    log_warn "⚠ $SECURITY_UPDATES security update(s) available"
else
    log_info "✓ No pending security updates"
fi

# Check for kernel updates
log_info ""
log_info "Checking for kernel updates..."

CURRENT_KERNEL=$(uname -r)
INSTALLED_KERNELS=$(dpkg -l | grep "^ii  linux-image-" | awk '{print $2}' | wc -l)
AVAILABLE_KERNELS=$(apt-cache search linux-image-generic | wc -l)

log_info "Current kernel: $CURRENT_KERNEL"
log_info "Installed kernel packages: $INSTALLED_KERNELS"

# Check if newer kernel is available
LATEST_KERNEL=$(apt-cache policy linux-image-generic 2>/dev/null | grep "Candidate:" | awk '{print $2}')
INSTALLED_KERNEL_VERSION=$(apt-cache policy linux-image-generic 2>/dev/null | grep "Installed:" | awk '{print $2}')

if [[ "$LATEST_KERNEL" != "$INSTALLED_KERNEL_VERSION" ]] && [[ "$LATEST_KERNEL" != "(none)" ]]; then
    log_warn "⚠ Newer kernel available: $LATEST_KERNEL (installed: $INSTALLED_KERNEL_VERSION)"
else
    log_info "✓ Kernel is up to date"
fi

# Check Ubuntu version and EOL status
log_info ""
log_info "Checking Ubuntu version and support status..."

UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)
UBUNTU_DESCRIPTION=$(lsb_release -ds)

log_info "Ubuntu version: $UBUNTU_VERSION ($UBUNTU_CODENAME)"
log_info "Description: $UBUNTU_DESCRIPTION"

# Check if Ubuntu Pro is available
if command -v pro &>/dev/null || command -v ubuntu-advantage-tools &>/dev/null; then
    PRO_STATUS=$(pro status 2>/dev/null | grep "^SERVICE" -A 20 || echo "Ubuntu Pro not configured")
    log_info ""
    log_info "Ubuntu Pro status:"
    echo "$PRO_STATUS" | while IFS= read -r line; do
        log_info "  $line"
    done
fi

# Check for pending reboots
log_info ""
log_info "Checking reboot requirements..."

if [[ -f /var/run/reboot-required ]]; then
    log_warn "⚠ REBOOT REQUIRED"
    
    if [[ -f /var/run/reboot-required.pkgs ]]; then
        log_info "Packages requiring reboot:"
        cat /var/run/reboot-required.pkgs | while IFS= read -r pkg; do
            log_info "  - $pkg"
        done
    fi
else
    log_info "✓ No reboot required"
fi

# Check disk space
log_info ""
log_info "Checking disk space..."

ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
ROOT_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

log_info "Root filesystem usage: ${ROOT_USAGE}% (available: ${ROOT_AVAIL})"

if [[ $ROOT_USAGE -gt 90 ]]; then
    log_warn "⚠ Root filesystem usage is high: ${ROOT_USAGE}%"
elif [[ $ROOT_USAGE -gt 80 ]]; then
    log_warn "Root filesystem usage is elevated: ${ROOT_USAGE}%"
else
    log_info "✓ Disk space is sufficient"
fi

# Check apt cache size
CACHE_SIZE=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
log_info "APT cache size: $CACHE_SIZE"

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info ""
log_info "=============================================="
log_info "Update Check Summary"
log_info "=============================================="
log_info "Ubuntu version: $UBUNTU_VERSION ($UBUNTU_CODENAME)"
log_info "Current kernel: $CURRENT_KERNEL"
log_info "Upgradable packages: $UPGRADABLE"
log_info "Security updates: $SECURITY_UPDATES"
log_info "Reboot required: $([ -f /var/run/reboot-required ] && echo 'YES' || echo 'NO')"
log_info "Disk usage: ${ROOT_USAGE}% (${ROOT_AVAIL} available)"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="

# Exit with appropriate code
if [[ $UPGRADABLE -gt 0 ]]; then
    log_warn ""
    log_warn "Updates are available. Run 'apt-get upgrade' to install."
    exit 1
else
    log_info "System is up to date!"
    exit 0
fi