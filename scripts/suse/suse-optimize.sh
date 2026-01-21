#!/bin/bash
#===================================================================================
# Script: optimize_suse.sh
# Description: Optimize SUSE/openSUSE system performance
# Author: XOAP Infrastructure Team
# Usage: ./optimize_suse.sh [--profile PROFILE]
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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            TUNED_PROFILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting system optimization for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
OPTIMIZATIONS_APPLIED=0

# Install tuned if available
log_info "Checking for tuned package..."

if ! command -v tuned-adm &>/dev/null; then
    log_info "Installing tuned..."
    
    if zypper install -y tuned; then
        log_info "✓ tuned installed"
        ((OPTIMIZATIONS_APPLIED++))
    else
        log_warn "Failed to install tuned, will apply manual optimizations"
    fi
else
    log_info "tuned is already installed"
fi

# Configure tuned if available
if command -v tuned-adm &>/dev/null; then
    log_info "Configuring tuned profile: $TUNED_PROFILE..."
    
    systemctl enable tuned
    systemctl start tuned
    
    if tuned-adm profile "$TUNED_PROFILE"; then
        log_info "✓ Tuned profile applied"
        ((OPTIMIZATIONS_APPLIED++))
    else
        log_warn "Failed to apply tuned profile"
    fi
else
    # Manual optimizations
    log_info "Applying manual system optimizations..."
    
    # Optimize swappiness
    log_info "Optimizing swappiness..."
    echo "vm.swappiness = 10" > /etc/sysctl.d/99-swappiness.conf
    sysctl -w vm.swappiness=10 &>/dev/null
    log_info "✓ Swappiness set to 10"
    ((OPTIMIZATIONS_APPLIED++))
    
    # Optimize I/O scheduler
    log_info "Optimizing I/O scheduler..."
    
    for disk in /sys/block/sd*/queue/scheduler /sys/block/vd*/queue/scheduler; do
        if [[ -f "$disk" ]]; then
            DEVICE=$(echo "$disk" | cut -d'/' -f4)
            echo "mq-deadline" > "$disk" 2>/dev/null || echo "deadline" > "$disk" 2>/dev/null || true
            log_info "  $DEVICE: $(cat "$disk" | grep -oP '\[\K[^\]]+')"
        fi
    done
    
    ((OPTIMIZATIONS_APPLIED++))
fi

# Optimize systemd services
log_info "Optimizing systemd settings..."

mkdir -p /etc/systemd/system.conf.d

cat > /etc/systemd/system.conf.d/99-optimization.conf <<'EOF'
[Manager]
DefaultTimeoutStartSec=90s
DefaultTimeoutStopSec=30s
DefaultLimitNOFILE=65536
EOF

systemctl daemon-reload

log_info "✓ systemd settings optimized"
((OPTIMIZATIONS_APPLIED++))

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "none")

log_info "=============================================="
log_info "System Optimization Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Tuned profile: $(command -v tuned-adm &>/dev/null && tuned-adm active 2>/dev/null | awk '{print $NF}' || echo 'not available')"
log_info "Optimizations applied: $OPTIMIZATIONS_APPLIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "System optimization completed!"