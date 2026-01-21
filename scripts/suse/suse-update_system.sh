#!/bin/bash
#===================================================================================
# Script: update_system_suse.sh
# Description: Update SUSE/openSUSE system with safety controls
# Author: XOAP Infrastructure Team
# Usage: ./update_system_suse.sh [--no-reboot] [--dist-upgrade]
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
AUTO_REBOOT="${AUTO_REBOOT:-true}"
DIST_UPGRADE="${DIST_UPGRADE:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-reboot)
            AUTO_REBOOT="false"
            shift
            ;;
        --dist-upgrade)
            DIST_UPGRADE="true"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting system update for SUSE..."
log_info "Auto reboot: $AUTO_REBOOT"
log_info "Distribution upgrade: $DIST_UPGRADE"

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_UPDATED=0

# Get current kernel version
CURRENT_KERNEL=$(uname -r)
log_info "Current kernel: $CURRENT_KERNEL"

# Backup list of installed packages
log_info "Backing up package list..."

rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/packages-before-update.txt
log_info "✓ Package list backed up to /tmp/packages-before-update.txt"

# Refresh repositories
log_info "Refreshing package repositories..."

if zypper refresh 2>&1 | tee /tmp/zypper-refresh.log; then
    log_info "✓ Repositories refreshed"
else
    log_error "Failed to refresh repositories"
    cat /tmp/zypper-refresh.log
    exit 1
fi

# Check for available updates
log_info "Checking for available updates..."

zypper list-updates &>/tmp/available-updates.log || true

AVAILABLE_UPDATES=$(grep -c "^v |" /tmp/available-updates.log || echo "0")
log_info "Available updates: $AVAILABLE_UPDATES"

if [[ "$AVAILABLE_UPDATES" -eq 0 ]]; then
    log_info "System is already up to date"
    exit 0
fi

# Display available updates
log_info "Available package updates:"
head -n 30 /tmp/available-updates.log | while IFS= read -r line; do
    [[ -n "$line" ]] && log_info "  $line"
done

# Perform update
if [[ "$DIST_UPGRADE" == "true" ]]; then
    log_info "Performing distribution upgrade..."
    UPDATE_CMD="zypper dist-upgrade -y --auto-agree-with-licenses"
else
    log_info "Performing package update..."
    UPDATE_CMD="zypper update -y --auto-agree-with-licenses"
fi

log_info "Executing: $UPDATE_CMD"

if $UPDATE_CMD 2>&1 | tee /tmp/update-output.log; then
    log_info "✓ System update completed"
else
    log_error "System update failed"
    tail -n 20 /tmp/update-output.log | while IFS= read -r line; do
        log_error "  $line"
    done
    exit 1
fi

# Count updated packages
PACKAGES_UPDATED=$(grep -c "Installing: " /tmp/update-output.log || echo "0")
PACKAGES_UPGRADED=$(grep -c "Upgrading: " /tmp/update-output.log || echo "0")

log_info "Packages installed: $PACKAGES_UPDATED"
log_info "Packages upgraded: $PACKAGES_UPGRADED"

# Backup updated package list
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/packages-after-update.txt

# Show package differences
if command -v diff &>/dev/null; then
    log_info "Package changes:"
    diff /tmp/packages-before-update.txt /tmp/packages-after-update.txt | grep "^>" | head -n 20 | while IFS= read -r line; do
        log_info "  $line"
    done
fi

# Check if kernel was updated
NEW_KERNEL=$(rpm -q kernel-default --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-default-//' || echo "$CURRENT_KERNEL")
log_info "Latest installed kernel: $NEW_KERNEL"

REBOOT_REQUIRED=false

if [[ "$NEW_KERNEL" != "$CURRENT_KERNEL" ]]; then
    log_info "Kernel was updated - reboot required"
    REBOOT_REQUIRED=true
fi

# Check for reboot-required flag
if zypper ps -s 2>/dev/null | grep -q "reboot-required"; then
    log_info "System requires reboot"
    REBOOT_REQUIRED=true
fi

# List services needing restart
log_info "Checking for services that need restart..."

if zypper ps 2>/dev/null | grep -q "The following"; then
    log_info "Services needing restart:"
    zypper ps 2>/dev/null | grep "^-" | while IFS= read -r line; do
        log_info "  $line"
    done
else
    log_info "No services need restart"
fi

# Clean package cache
log_info "Cleaning package cache..."

zypper clean --all &>/dev/null || log_warn "Failed to clean cache"

# Perform reboot if required and enabled
if [[ "$REBOOT_REQUIRED" == "true" ]]; then
    if [[ "$AUTO_REBOOT" == "true" ]]; then
        log_info "System reboot required - rebooting in 60 seconds..."
        log_info "Cancel with: shutdown -c"
        
        shutdown -r +1 "System reboot required after updates" &
        
        log_info "Reboot scheduled"
    else
        log_warn "System reboot required but auto-reboot is disabled"
        log_warn "Please reboot the system manually: reboot"
    fi
else
    log_info "No reboot required"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "System Update Summary"
log_info "=============================================="
log_info "Update type: $([ "$DIST_UPGRADE" == "true" ] && echo 'Distribution upgrade' || echo 'Package update')"
log_info "Packages installed: $PACKAGES_UPDATED"
log_info "Packages upgraded: $PACKAGES_UPGRADED"
log_info "Kernel updated: $([ "$NEW_KERNEL" != "$CURRENT_KERNEL" ] && echo 'yes' || echo 'no')"
log_info "Current kernel: $CURRENT_KERNEL"
log_info "Latest kernel: $NEW_KERNEL"
log_info "Reboot required: $([ "$REBOOT_REQUIRED" == "true" ] && echo 'yes' || echo 'no')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "System update completed!"