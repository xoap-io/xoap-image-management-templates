#!/bin/bash
#===================================================================================
# Script: remove_old_kernels.sh
# Description: Remove old kernel versions on RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./remove_old_kernels.sh [keep_count]
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

log_info "Starting old kernel removal..."

# Configuration
KEEP_COUNT="${1:-2}"  # Keep current + 1 previous by default
START_TIME=$(date +%s)
KERNELS_REMOVED=0
DISK_FREED=0

# Get disk usage before
DISK_BEFORE=$(df /boot | awk 'NR==2 {print $3}')

# Display current kernel
CURRENT_KERNEL=$(uname -r)
log_info "Current running kernel: $CURRENT_KERNEL"

# List all installed kernels
log_info "Listing all installed kernels..."
ALL_KERNELS=$(rpm -qa | grep -E '^kernel-[0-9]' | sort -V)

if [[ -z "$ALL_KERNELS" ]]; then
    log_info "No additional kernels found to remove"
    exit 0
fi

TOTAL_KERNELS=$(echo "$ALL_KERNELS" | wc -l)
log_info "Total kernels installed: $TOTAL_KERNELS"

echo "$ALL_KERNELS" | while IFS= read -r kernel; do
    log_info "  - $kernel"
done

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

log_info "Using package manager: $PKG_MGR"

# Get list of old kernels to remove
log_info "Identifying old kernels (keeping $KEEP_COUNT most recent)..."

if [[ "$PKG_MGR" == "dnf" ]]; then
    OLD_KERNELS=$(dnf repoquery --installonly --latest-limit=-${KEEP_COUNT} -q 2>/dev/null || echo "")
else
    # For yum, we need to use package-cleanup
    if command -v package-cleanup &>/dev/null; then
        OLD_KERNELS=$(package-cleanup --oldkernels --count=${KEEP_COUNT} --assumeno 2>&1 | grep "kernel-" | awk '{print $1}' || echo "")
    else
        log_warn "package-cleanup not available, using alternative method..."
        # Alternative: manually list kernels and keep newest
        OLD_KERNELS=$(rpm -qa kernel | sort -V | head -n -${KEEP_COUNT} || echo "")
    fi
fi

if [[ -z "$OLD_KERNELS" ]]; then
    log_info "No old kernels to remove (keeping $KEEP_COUNT most recent)"
    exit 0
fi

KERNEL_COUNT=$(echo "$OLD_KERNELS" | wc -l)
log_info "Found $KERNEL_COUNT old kernel(s) to remove:"

echo "$OLD_KERNELS" | while IFS= read -r kernel; do
    log_info "  - $kernel"
done

# Confirm removal
log_info "Removing old kernels..."

for kernel in $OLD_KERNELS; do
    if [[ -n "$kernel" ]]; then
        log_info "Removing: $kernel"
        
        if $PKG_MGR remove -y "$kernel" 2>&1 | tee -a /tmp/kernel-removal.log; then
            KERNELS_REMOVED=$((KERNELS_REMOVED + 1))
            log_info "Successfully removed: $kernel"
        else
            log_warn "Failed to remove: $kernel"
        fi
    fi
done

# Clean up package cache
log_info "Cleaning package cache..."
$PKG_MGR clean all

# Get disk usage after
DISK_AFTER=$(df /boot | awk 'NR==2 {print $3}')
DISK_FREED=$((DISK_BEFORE - DISK_AFTER))

# Verify current kernel is still installed
if rpm -q "kernel-${CURRENT_KERNEL}" &>/dev/null || rpm -q "kernel-core-${CURRENT_KERNEL}" &>/dev/null; then
    log_info "✓ Current kernel is still installed"
else
    log_warn "✗ Current kernel package verification failed (may be normal)"
fi

# List remaining kernels
log_info "Remaining installed kernels:"
rpm -qa | grep -E '^kernel-[0-9]' | sort -V | while IFS= read -r kernel; do
    log_info "  - $kernel"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Kernel Removal Summary"
log_info "=============================================="
log_info "Kernels removed: $KERNELS_REMOVED"
log_info "Kernels kept: $KEEP_COUNT (most recent)"
log_info "Current kernel: $CURRENT_KERNEL"

if [[ $DISK_FREED -gt 0 ]]; then
    log_info "/boot space freed: $(numfmt --to=iec-i --suffix=B $((DISK_FREED * 1024)))"
else
    log_info "/boot space change: minimal"
fi

log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Kernel removal completed successfully!"