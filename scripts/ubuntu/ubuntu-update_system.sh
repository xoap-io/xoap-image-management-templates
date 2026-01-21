#!/bin/bash
#===================================================================================
# Script: ubuntu-update_system.sh
# Description: Update Ubuntu system packages
# Author: XOAP Infrastructure Team
# Usage: ./ubuntu-update_system.sh [--dist-upgrade]
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

# Variables
DIST_UPGRADE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dist-upgrade)
            DIST_UPGRADE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting system update for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_UPGRADED=0
PACKAGES_INSTALLED=0
PACKAGES_REMOVED=0

# Get initial system state
DISK_BEFORE=$(df / | awk 'NR==2 {print $3}')
KERNEL_BEFORE=$(uname -r)

log_info "System state before update:"
log_info "  Kernel: $KERNEL_BEFORE"
log_info "  Disk usage: $DISK_BEFORE KB"

# Wait for apt locks to be released
log_info "Checking for active apt processes..."

wait_for_apt() {
    local max_wait=300
    local waited=0
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        
        if [[ $waited -ge $max_wait ]]; then
            log_error "Timeout waiting for apt locks"
            exit 1
        fi
        
        log_info "Waiting for apt locks to be released..."
        sleep 5
        ((waited+=5))
    done
}

wait_for_apt

# Update package lists
log_info "Updating package lists from repositories..."

if apt-get update 2>&1 | tee /tmp/apt_update.log; then
    log_info "✓ Package lists updated successfully"
    
    # Count available upgrades
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' || echo "0")
    log_info "Packages available for upgrade: $UPGRADABLE"
else
    log_error "Failed to update package lists"
    exit 1
fi

# Upgrade installed packages
log_info "Upgrading installed packages..."

if apt-get upgrade -y 2>&1 | tee /tmp/apt_upgrade.log; then
    # Parse upgrade output for statistics
    PACKAGES_UPGRADED=$(grep -oP '\d+(?= upgraded)' /tmp/apt_upgrade.log | head -1 || echo "0")
    PACKAGES_INSTALLED=$(grep -oP '\d+(?= newly installed)' /tmp/apt_upgrade.log | head -1 || echo "0")
    PACKAGES_REMOVED=$(grep -oP '\d+(?= to remove)' /tmp/apt_upgrade.log | head -1 || echo "0")
    
    log_info "✓ Package upgrade completed"
    log_info "  Upgraded: $PACKAGES_UPGRADED packages"
    log_info "  Newly installed: $PACKAGES_INSTALLED packages"
    log_info "  Removed: $PACKAGES_REMOVED packages"
else
    log_error "Package upgrade failed"
    exit 1
fi

# Perform distribution upgrade if requested
if [[ "$DIST_UPGRADE" == true ]]; then
    log_info "Performing distribution upgrade (dist-upgrade)..."
    
    if apt-get dist-upgrade -y 2>&1 | tee /tmp/apt_dist_upgrade.log; then
        log_info "✓ Distribution upgrade completed"
        
        # Check for additional packages upgraded during dist-upgrade
        DIST_UPGRADED=$(grep -oP '\d+(?= upgraded)' /tmp/apt_dist_upgrade.log | head -1 || echo "0")
        if [[ $DIST_UPGRADED -gt 0 ]]; then
            log_info "Additional packages upgraded during dist-upgrade: $DIST_UPGRADED"
            PACKAGES_UPGRADED=$((PACKAGES_UPGRADED + DIST_UPGRADED))
        fi
    else
        log_warn "Distribution upgrade encountered issues (may not be critical)"
    fi
fi

# Remove unused packages
log_info "Removing unused packages (autoremove)..."

AUTOREMOVE_OUTPUT=$(apt-get autoremove --purge -y 2>&1 | tee /tmp/apt_autoremove.log)
AUTOREMOVE_COUNT=$(echo "$AUTOREMOVE_OUTPUT" | grep -oP '\d+(?= to remove)' || echo "0")

if [[ -n "$AUTOREMOVE_COUNT" ]] && [[ "$AUTOREMOVE_COUNT" -gt 0 ]]; then
    log_info "✓ Removed $AUTOREMOVE_COUNT unused packages"
    PACKAGES_REMOVED=$((PACKAGES_REMOVED + AUTOREMOVE_COUNT))
else
    log_info "No unused packages to remove"
fi

# Clean package cache
log_info "Cleaning package cache..."

apt-get clean

CACHE_SIZE=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
log_info "✓ Package cache cleaned (current size: $CACHE_SIZE)"

# Check if reboot is required
log_info "Checking if reboot is required..."

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

# Get final system state
DISK_AFTER=$(df / | awk 'NR==2 {print $3}')
KERNEL_AFTER=$(uname -r)

DISK_CHANGE=$((DISK_AFTER - DISK_BEFORE))

log_info "System state after update:"
log_info "  Kernel: $KERNEL_AFTER"
log_info "  Disk usage: $DISK_AFTER KB (change: ${DISK_CHANGE} KB)"

# Check for kernel update
if [[ "$KERNEL_BEFORE" != "$KERNEL_AFTER" ]]; then
    log_warn "Kernel was updated from $KERNEL_BEFORE to $KERNEL_AFTER"
    log_warn "Reboot required to use new kernel"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "System Update Summary"
log_info "=============================================="
log_info "Packages upgraded: $PACKAGES_UPGRADED"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Packages removed: $PACKAGES_REMOVED"
log_info "Distribution upgrade: $([ "$DIST_UPGRADE" == true ] && echo 'yes' || echo 'no')"
log_info "Reboot required: $([ -f /var/run/reboot-required ] && echo 'YES' || echo 'NO')"
log_info "Disk space change: ${DISK_CHANGE} KB"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "System update completed successfully!"

if [[ -f /var/run/reboot-required ]]; then
    log_warn ""
    log_warn "IMPORTANT: System reboot is required"
    log_warn "Run: sudo reboot"
fi