#!/bin/bash
#===================================================================================
# Script: remove_old_kernels_ubuntu.sh
# Description: Remove old kernel packages from Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./remove_old_kernels_ubuntu.sh [--keep COUNT]
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
KEEP_KERNELS="${KEEP_KERNELS:-2}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep)
            KEEP_KERNELS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting old kernel cleanup for Ubuntu..."
log_info "Kernels to keep: $KEEP_KERNELS"

# Statistics tracking
START_TIME=$(date +%s)
KERNELS_REMOVED=0
SPACE_FREED=0

# Get current running kernel
CURRENT_KERNEL=$(uname -r)
log_info "Current running kernel: $CURRENT_KERNEL"

# List all installed kernels
log_info "Listing installed kernels..."

INSTALLED_KERNELS=$(dpkg -l | grep "^ii.*linux-image-[0-9]" | awk '{print $2}' | sort -V)

if [[ -z "$INSTALLED_KERNELS" ]]; then
    log_info "No kernels found to process"
    exit 0
fi

KERNEL_COUNT=$(echo "$INSTALLED_KERNELS" | wc -l)
log_info "Total installed kernels: $KERNEL_COUNT"

log_info "Installed kernels:"
echo "$INSTALLED_KERNELS" | while IFS= read -r kernel; do
    KERNEL_VERSION=$(echo "$kernel" | sed 's/linux-image-//')
    KERNEL_SIZE=$(dpkg -L "$kernel" 2>/dev/null | xargs -I {} du -hs {} 2>/dev/null | awk '{s+=$1}END{print s}' || echo "0")
    log_info "  $kernel"
done

# Check if we need to remove any kernels
if [[ "$KERNEL_COUNT" -le "$KEEP_KERNELS" ]]; then
    log_info "Only $KERNEL_COUNT kernel(s) installed, no cleanup needed"
    exit 0
fi

# Calculate how many kernels to remove
KERNELS_TO_REMOVE=$((KERNEL_COUNT - KEEP_KERNELS))
log_info "Kernels to remove: $KERNELS_TO_REMOVE"

# Get list of kernels to remove (oldest ones, excluding current)
KERNELS_FOR_REMOVAL=$(echo "$INSTALLED_KERNELS" | head -n "$KERNELS_TO_REMOVE")

log_info "Kernels marked for removal:"
echo "$KERNELS_FOR_REMOVAL" | while IFS= read -r kernel; do
    KERNEL_VERSION=$(echo "$kernel" | sed 's/linux-image-//')
    
    if [[ "$KERNEL_VERSION" == "$CURRENT_KERNEL" ]]; then
        log_warn "  $kernel (CURRENT - SKIPPING)"
    else
        log_info "  $kernel"
    fi
done

# Remove old kernels
log_info "Removing old kernels..."

for kernel_pkg in $KERNELS_FOR_REMOVAL; do
    KERNEL_VERSION=$(echo "$kernel_pkg" | sed 's/linux-image-//')
    
    # Skip if this is the current running kernel
    if [[ "$KERNEL_VERSION" == "$CURRENT_KERNEL" ]]; then
        log_warn "Skipping current running kernel: $kernel_pkg"
        continue
    fi
    
    log_info "Removing kernel: $kernel_pkg..."
    
    # Remove kernel and related packages
    RELATED_PACKAGES=$(dpkg -l | grep "^ii.*linux-.*${KERNEL_VERSION}" | awk '{print $2}')
    
    if [[ -n "$RELATED_PACKAGES" ]]; then
        if DEBIAN_FRONTEND=noninteractive apt-get purge -y $RELATED_PACKAGES 2>&1 | tee /tmp/kernel-remove.log; then
            log_info "  ✓ Removed $kernel_pkg and related packages"
            ((KERNELS_REMOVED++))
        else
            log_error "  ✗ Failed to remove $kernel_pkg"
            cat /tmp/kernel-remove.log | tail -n 10 | while IFS= read -r line; do
                log_error "    $line"
            done
        fi
    fi
done

# Run autoremove to clean up dependencies
log_info "Cleaning up dependencies..."

DEBIAN_FRONTEND=noninteractive apt-get autoremove -y &>/dev/null || log_warn "Failed to run autoremove"

# Update GRUB configuration
log_info "Updating GRUB configuration..."

if update-grub &>/dev/null; then
    log_info "✓ GRUB configuration updated"
else
    log_warn "Failed to update GRUB configuration"
fi

# Clean up boot directory
log_info "Cleaning up /boot directory..."

BOOT_USAGE_BEFORE=$(df -h /boot 2>/dev/null | tail -n1 | awk '{print $5}' || echo "N/A")
log_info "Boot partition usage before: $BOOT_USAGE_BEFORE"

BOOT_USAGE_AFTER=$(df -h /boot 2>/dev/null | tail -n1 | awk '{print $5}' || echo "N/A")
log_info "Boot partition usage after: $BOOT_USAGE_AFTER"

# List remaining kernels
log_info "Remaining installed kernels:"

REMAINING_KERNELS=$(dpkg -l | grep "^ii.*linux-image-[0-9]" | awk '{print $2}' | sort -V)
REMAINING_COUNT=$(echo "$REMAINING_KERNELS" | wc -l)

echo "$REMAINING_KERNELS" | while IFS= read -r kernel; do
    KERNEL_VERSION=$(echo "$kernel" | sed 's/linux-image-//')
    
    if [[ "$KERNEL_VERSION" == "$CURRENT_KERNEL" ]]; then
        log_info "  $kernel [CURRENT]"
    else
        log_info "  $kernel"
    fi
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Kernel Cleanup Summary"
log_info "=============================================="
log_info "Current kernel: $CURRENT_KERNEL"
log_info "Kernels before cleanup: $KERNEL_COUNT"
log_info "Kernels after cleanup: $REMAINING_COUNT"
log_info "Kernels removed: $KERNELS_REMOVED"
log_info "Boot usage before: $BOOT_USAGE_BEFORE"
log_info "Boot usage after: $BOOT_USAGE_AFTER"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Kernel cleanup completed!"