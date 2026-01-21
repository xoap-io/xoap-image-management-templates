#!/bin/bash
#===================================================================================
# Script: remove_old_kernels_suse.sh
# Description: Remove old kernel packages from SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./remove_old_kernels_suse.sh [--keep COUNT]
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

log_info "Starting old kernel cleanup for SUSE..."
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

INSTALLED_KERNELS=$(rpm -qa | grep "^kernel-default-[0-9]" | sort -V)

if [[ -z "$INSTALLED_KERNELS" ]]; then
    log_info "No kernels found to process"
    exit 0
fi

KERNEL_COUNT=$(echo "$INSTALLED_KERNELS" | wc -l)
log_info "Total installed kernels: $KERNEL_COUNT"

log_info "Installed kernels:"
echo "$INSTALLED_KERNELS" | while IFS= read -r kernel; do
    KERNEL_VERSION=$(rpm -q "$kernel" --queryformat '%{VERSION}-%{RELEASE}')
    KERNEL_SIZE=$(rpm -q "$kernel" --queryformat '%{SIZE}')
    KERNEL_SIZE_MB=$((KERNEL_SIZE / 1024 / 1024))
    log_info "  $kernel ($KERNEL_SIZE_MB MB)"
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
    KERNEL_VERSION=$(rpm -q "$kernel" --queryformat '%{VERSION}-%{RELEASE}')
    
    # Check if this is the current running kernel
    if [[ "$KERNEL_VERSION" == "$CURRENT_KERNEL" ]]; then
        log_warn "  $kernel (CURRENT - SKIPPING)"
    else
        KERNEL_SIZE=$(rpm -q "$kernel" --queryformat '%{SIZE}')
        KERNEL_SIZE_MB=$((KERNEL_SIZE / 1024 / 1024))
        log_info "  $kernel ($KERNEL_SIZE_MB MB)"
    fi
done

# Remove old kernels
log_info "Removing old kernels..."

for kernel_pkg in $KERNELS_FOR_REMOVAL; do
    KERNEL_VERSION=$(rpm -q "$kernel_pkg" --queryformat '%{VERSION}-%{RELEASE}')
    
    # Skip if this is the current running kernel
    if [[ "$KERNEL_VERSION" == "$CURRENT_KERNEL" ]]; then
        log_warn "Skipping current running kernel: $kernel_pkg"
        continue
    fi
    
    log_info "Removing kernel: $kernel_pkg..."
    
    # Get size before removal
    KERNEL_SIZE=$(rpm -q "$kernel_pkg" --queryformat '%{SIZE}' 2>/dev/null || echo "0")
    KERNEL_SIZE_MB=$((KERNEL_SIZE / 1024 / 1024))
    
    # Remove kernel and related packages
    if zypper remove -y "$kernel_pkg" 2>&1 | tee /tmp/kernel-remove.log; then
        log_info "  ✓ Removed $kernel_pkg ($KERNEL_SIZE_MB MB)"
        ((KERNELS_REMOVED++))
        SPACE_FREED=$((SPACE_FREED + KERNEL_SIZE_MB))
    else
        log_error "  ✗ Failed to remove $kernel_pkg"
        cat /tmp/kernel-remove.log | tail -n 10 | while IFS= read -r line; do
            log_error "    $line"
        done
    fi
    
    # Remove associated kernel modules if they exist
    if [[ -d "/lib/modules/$KERNEL_VERSION" ]]; then
        log_info "  Removing kernel modules for $KERNEL_VERSION..."
        rm -rf "/lib/modules/$KERNEL_VERSION"
        log_info "  ✓ Kernel modules removed"
    fi
done

# Update GRUB configuration
log_info "Updating GRUB configuration..."

if [[ -d /sys/firmware/efi ]]; then
    GRUB_CFG="/boot/efi/EFI/opensuse/grub.cfg"
else
    GRUB_CFG="/boot/grub2/grub.cfg"
fi

if grub2-mkconfig -o "$GRUB_CFG" &>/dev/null; then
    log_info "✓ GRUB configuration updated"
else
    log_warn "Failed to update GRUB configuration"
fi

# Clean up boot directory
log_info "Cleaning up /boot directory..."

BOOT_USAGE_BEFORE=$(df -h /boot | tail -n1 | awk '{print $5}')
log_info "Boot partition usage before: $BOOT_USAGE_BEFORE"

# Remove orphaned initrd and vmlinuz files
for file in /boot/initrd-* /boot/vmlinuz-*; do
    if [[ -f "$file" ]]; then
        KERNEL_VER=$(basename "$file" | sed 's/initrd-//;s/vmlinuz-//')
        
        # Check if kernel package still exists
        if ! rpm -qa | grep -q "kernel-default.*$KERNEL_VER"; then
            log_info "  Removing orphaned file: $(basename "$file")"
            rm -f "$file"
        fi
    fi
done

BOOT_USAGE_AFTER=$(df -h /boot | tail -n1 | awk '{print $5}')
log_info "Boot partition usage after: $BOOT_USAGE_AFTER"

# List remaining kernels
log_info "Remaining installed kernels:"

REMAINING_KERNELS=$(rpm -qa | grep "^kernel-default-[0-9]" | sort -V)
REMAINING_COUNT=$(echo "$REMAINING_KERNELS" | wc -l)

echo "$REMAINING_KERNELS" | while IFS= read -r kernel; do
    KERNEL_VERSION=$(rpm -q "$kernel" --queryformat '%{VERSION}-%{RELEASE}')
    KERNEL_SIZE=$(rpm -q "$kernel" --queryformat '%{SIZE}')
    KERNEL_SIZE_MB=$((KERNEL_SIZE / 1024 / 1024))
    
    if [[ "$KERNEL_VERSION" == "$CURRENT_KERNEL" ]]; then
        log_info "  $kernel ($KERNEL_SIZE_MB MB) [CURRENT]"
    else
        log_info "  $kernel ($KERNEL_SIZE_MB MB)"
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
log_info "Space freed: ~${SPACE_FREED} MB"
log_info "Boot usage before: $BOOT_USAGE_BEFORE"
log_info "Boot usage after: $BOOT_USAGE_AFTER"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Kernel cleanup completed!"