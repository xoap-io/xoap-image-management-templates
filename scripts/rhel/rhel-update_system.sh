#!/bin/bash
#===================================================================================
# Script: update_system.sh
# Description: Update RHEL/CentOS system with safety controls
# Author: XOAP Infrastructure Team
# Usage: ./update_system.sh [--security-only] [--no-reboot] [--kernel]
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
SECURITY_ONLY="${SECURITY_ONLY:-false}"
AUTO_REBOOT="${AUTO_REBOOT:-true}"
UPDATE_KERNEL="${UPDATE_KERNEL:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --security-only)
            SECURITY_ONLY="true"
            shift
            ;;
        --no-reboot)
            AUTO_REBOOT="false"
            shift
            ;;
        --kernel)
            UPDATE_KERNEL="true"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting system update..."
log_info "Security only: $SECURITY_ONLY"
log_info "Auto reboot: $AUTO_REBOOT"
log_info "Kernel updates: $UPDATE_KERNEL"

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_UPDATED=0
SECURITY_UPDATES=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

# Check for available updates
log_info "Checking for available updates..."

if [[ "$PKG_MGR" == "dnf" ]]; then
    dnf check-update &>/tmp/check-updates.log || true
    AVAILABLE_UPDATES=$(grep -v "^$" /tmp/check-updates.log | grep -v "^Last metadata" | wc -l || echo "0")
else
    yum check-update &>/tmp/check-updates.log || true
    AVAILABLE_UPDATES=$(grep -v "^$" /tmp/check-updates.log | grep -v "^Loaded plugins" | wc -l || echo "0")
fi

log_info "Available updates: $AVAILABLE_UPDATES"

if [[ "$AVAILABLE_UPDATES" -eq 0 ]]; then
    log_info "System is already up to date"
    exit 0
fi

# Display available updates
log_info "Available package updates:"
head -n 20 /tmp/check-updates.log | while IFS= read -r line; do
    [[ -n "$line" ]] && log_info "  $line"
done

# Check for security updates
log_info "Checking for security updates..."

if [[ "$PKG_MGR" == "dnf" ]]; then
    SECURITY_UPDATES=$(dnf updateinfo list security 2>/dev/null | grep -c "RHSA" || echo "0")
else
    SECURITY_UPDATES=$(yum updateinfo list security 2>/dev/null | grep -c "RHSA" || echo "0")
fi

log_info "Available security updates: $SECURITY_UPDATES"

# Get current kernel version
CURRENT_KERNEL=$(uname -r)
log_info "Current kernel: $CURRENT_KERNEL"

# Backup list of installed packages
log_info "Backing up package list..."

rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/packages-before-update.txt
log_info "✓ Package list backed up to /tmp/packages-before-update.txt"

# Perform update
if [[ "$SECURITY_ONLY" == "true" ]]; then
    log_info "Applying security updates only..."
    
    if [[ "$PKG_MGR" == "dnf" ]]; then
        UPDATE_CMD="dnf update --security -y"
    else
        UPDATE_CMD="yum update --security -y"
    fi
else
    log_info "Applying all available updates..."
    
    if [[ "$UPDATE_KERNEL" == "false" ]]; then
        UPDATE_CMD="$PKG_MGR update -y --exclude=kernel*"
        log_info "Kernel updates excluded"
    else
        UPDATE_CMD="$PKG_MGR update -y"
        log_info "Including kernel updates"
    fi
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
PACKAGES_UPDATED=$(grep -c "^Upgraded:" /tmp/update-output.log || echo "0")
PACKAGES_INSTALLED=$(grep -c "^Installed:" /tmp/update-output.log || echo "0")

log_info "Packages upgraded: $PACKAGES_UPDATED"
log_info "Packages installed: $PACKAGES_INSTALLED"

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
NEW_KERNEL=$(rpm -q kernel --last | head -n1 | awk '{print $1}' | sed 's/kernel-//')
log_info "Latest installed kernel: $NEW_KERNEL"

REBOOT_REQUIRED=false

if [[ "$NEW_KERNEL" != "$CURRENT_KERNEL" ]]; then
    log_info "Kernel was updated - reboot required"
    REBOOT_REQUIRED=true
elif [[ -f /var/run/reboot-required ]]; then
    log_info "Reboot required by package updates"
    REBOOT_REQUIRED=true
fi

# Check for services needing restart
log_info "Checking for services that need restart..."

if command -v needs-restarting &>/dev/null; then
    SERVICES_NEEDING_RESTART=$(needs-restarting -s 2>/dev/null || echo "")
    
    if [[ -n "$SERVICES_NEEDING_RESTART" ]]; then
        log_info "Services needing restart:"
        echo "$SERVICES_NEEDING_RESTART" | while IFS= read -r service; do
            log_info "  $service"
        done
    else
        log_info "No services need restart"
    fi
else
    log_info "needs-restarting utility not available"
fi

# Clean package cache
log_info "Cleaning package cache..."

$PKG_MGR clean all &>/dev/null || log_warn "Failed to clean cache"

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
log_info "Update type: $([ "$SECURITY_ONLY" == "true" ] && echo 'Security only' || echo 'All packages')"
log_info "Packages upgraded: $PACKAGES_UPDATED"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Security updates: $SECURITY_UPDATES"
log_info "Kernel updated: $([ "$NEW_KERNEL" != "$CURRENT_KERNEL" ] && echo 'yes' || echo 'no')"
log_info "Current kernel: $CURRENT_KERNEL"
log_info "Latest kernel: $NEW_KERNEL"
log_info "Reboot required: $([ "$REBOOT_REQUIRED" == "true" ] && echo 'yes' || echo 'no')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "System update completed!"