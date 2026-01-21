#!/bin/bash
#===================================================================================
# Script: optimize_rhel.sh
# Description: Optimize RHEL system performance with tuned profiles
# Author: XOAP Infrastructure Team
# Usage: ./optimize_rhel.sh [--profile PROFILE]
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
TUNED_PROFILE="${TUNED_PROFILE:-virtual-guest}"
DETECT_PROFILE="${DETECT_PROFILE:-true}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            TUNED_PROFILE="$2"
            DETECT_PROFILE="false"
            shift 2
            ;;
        --no-detect)
            DETECT_PROFILE="false"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting RHEL system optimization..."

# Statistics tracking
START_TIME=$(date +%s)
OPTIMIZATIONS_APPLIED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

# Install tuned if not present
if ! command -v tuned-adm &>/dev/null; then
    log_info "Installing tuned package..."
    
    if $PKG_MGR install -y tuned; then
        log_info "✓ tuned installed successfully"
        ((OPTIMIZATIONS_APPLIED++))
    else
        log_error "Failed to install tuned"
        exit 1
    fi
else
    log_info "tuned is already installed"
fi

# Enable and start tuned service
log_info "Enabling tuned service..."

systemctl enable tuned
systemctl start tuned

if systemctl is-active --quiet tuned; then
    log_info "✓ tuned service is running"
else
    log_error "Failed to start tuned service"
    exit 1
fi

# Detect optimal profile if requested
if [[ "$DETECT_PROFILE" == "true" ]]; then
    log_info "Detecting optimal tuned profile..."
    
    VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "none")
    log_info "Virtualization platform: $VIRT_PLATFORM"
    
    case "$VIRT_PLATFORM" in
        kvm|qemu|vmware|microsoft|xen|oracle)
            TUNED_PROFILE="virtual-guest"
            log_info "Detected virtual machine - using virtual-guest profile"
            ;;
        none)
            # Physical machine - check if it's a server
            if [[ -d /sys/class/net/eth0 ]] || [[ -d /sys/class/net/ens* ]]; then
                TUNED_PROFILE="throughput-performance"
                log_info "Detected physical server - using throughput-performance profile"
            else
                TUNED_PROFILE="balanced"
                log_info "Using balanced profile"
            fi
            ;;
        *)
            TUNED_PROFILE="virtual-guest"
            log_warn "Unknown virtualization platform - defaulting to virtual-guest"
            ;;
    esac
fi

# Get current profile
CURRENT_PROFILE=$(tuned-adm active 2>/dev/null | grep "Current active profile:" | awk '{print $NF}' || echo "none")
log_info "Current tuned profile: $CURRENT_PROFILE"

# List available profiles
log_info "Available tuned profiles:"
tuned-adm list 2>/dev/null | grep "^-" | while IFS= read -r line; do
    log_info "  $line"
done

# Apply selected profile
if [[ "$CURRENT_PROFILE" == "$TUNED_PROFILE" ]]; then
    log_info "Profile '$TUNED_PROFILE' is already active"
else
    log_info "Applying tuned profile: $TUNED_PROFILE"
    
    if tuned-adm profile "$TUNED_PROFILE"; then
        log_info "✓ Profile applied successfully"
        ((OPTIMIZATIONS_APPLIED++))
    else
        log_error "Failed to apply profile"
        exit 1
    fi
fi

# Verify profile application
sleep 2

NEW_PROFILE=$(tuned-adm active 2>/dev/null | grep "Current active profile:" | awk '{print $NF}' || echo "none")

if [[ "$NEW_PROFILE" == "$TUNED_PROFILE" ]]; then
    log_info "✓ Profile verification successful"
else
    log_warn "Profile verification failed - expected '$TUNED_PROFILE', got '$NEW_PROFILE'"
fi

# Display profile details
log_info "Profile details:"
tuned-adm profile_info "$TUNED_PROFILE" 2>/dev/null | while IFS= read -r line; do
    log_info "  $line"
done

# Additional optimizations
log_info "Applying additional system optimizations..."

# Disable transparent huge pages for database workloads (optional)
if [[ "$TUNED_PROFILE" == *"database"* ]] || [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
    log_info "Checking transparent huge pages configuration..."
    
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
        THP_STATUS=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
        log_info "Current THP status: $THP_STATUS"
    fi
fi

# Optimize swappiness for virtual machines
if [[ "$VIRT_PLATFORM" != "none" ]]; then
    CURRENT_SWAPPINESS=$(cat /proc/sys/vm/swappiness)
    log_info "Current swappiness: $CURRENT_SWAPPINESS"
    
    if [[ "$CURRENT_SWAPPINESS" -gt 10 ]]; then
        log_info "Adjusting swappiness for virtual machine..."
        echo "vm.swappiness = 10" >> /etc/sysctl.d/99-vm-swappiness.conf
        sysctl -w vm.swappiness=10 &>/dev/null || log_warn "Failed to set swappiness"
        ((OPTIMIZATIONS_APPLIED++))
    fi
fi

# Optimize I/O scheduler
log_info "Checking I/O schedulers..."

for disk in /sys/block/sd*/queue/scheduler /sys/block/vd*/queue/scheduler /sys/block/nvme*/queue/scheduler; do
    if [[ -f "$disk" ]]; then
        DEVICE=$(echo "$disk" | cut -d'/' -f4)
        SCHEDULER=$(cat "$disk" | grep -oP '\[\K[^\]]+')
        log_info "  $DEVICE: $SCHEDULER"
    fi
done

# Enable automatic tuning updates
log_info "Configuring tuned for automatic updates..."

if grep -q "^dynamic_tuning = 1" /etc/tuned/tuned-main.conf 2>/dev/null; then
    log_info "Dynamic tuning is already enabled"
else
    sed -i 's/^dynamic_tuning = 0/dynamic_tuning = 1/' /etc/tuned/tuned-main.conf 2>/dev/null || \
        echo "dynamic_tuning = 1" >> /etc/tuned/tuned-main.conf
    log_info "✓ Dynamic tuning enabled"
    ((OPTIMIZATIONS_APPLIED++))
fi

# Restart tuned to apply all changes
log_info "Restarting tuned service..."
systemctl restart tuned

sleep 2

if systemctl is-active --quiet tuned; then
    log_info "✓ tuned service restarted successfully"
else
    log_error "Failed to restart tuned service"
    exit 1
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "RHEL Optimization Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Applied profile: $(tuned-adm active 2>/dev/null | grep "Current active profile:" | awk '{print $NF}')"
log_info "Previous profile: $CURRENT_PROFILE"
log_info "Optimizations applied: $OPTIMIZATIONS_APPLIED"
log_info "Dynamic tuning: $(grep -q "^dynamic_tuning = 1" /etc/tuned/tuned-main.conf && echo 'enabled' || echo 'disabled')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "System optimization completed!"
log_info ""
log_info "Available tuned profiles:"
log_info "  - balanced: General purpose profile"
log_info "  - throughput-performance: Maximum throughput"
log_info "  - latency-performance: Low latency"
log_info "  - virtual-guest: Optimized for VMs"
log_info "  - virtual-host: Optimized for hypervisors"
log_info ""
log_info "To change profile: tuned-adm profile <profile-name>"