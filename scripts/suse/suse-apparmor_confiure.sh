#!/bin/bash
#===================================================================================
# Script: apparmor_configure_suse.sh
# Description: Configure AppArmor security for SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./apparmor_configure_suse.sh [--mode enforce|complain]
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
APPARMOR_MODE="${APPARMOR_MODE:-enforce}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            APPARMOR_MODE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting AppArmor configuration for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
PROFILES_CONFIGURED=0

# Install AppArmor if not present
if ! command -v aa-status &>/dev/null; then
    log_info "Installing AppArmor packages..."
    
    if zypper install -y apparmor-utils apparmor-profiles apparmor-profiles-extra; then
        log_info "✓ AppArmor packages installed"
        ((PROFILES_CONFIGURED++))
    else
        log_error "Failed to install AppArmor packages"
        exit 1
    fi
else
    log_info "AppArmor is already installed"
fi

# Enable AppArmor service
log_info "Enabling AppArmor service..."

systemctl enable apparmor
systemctl start apparmor

# Wait for AppArmor to be ready
sleep 2

if systemctl is-active --quiet apparmor; then
    log_info "✓ AppArmor service is running"
else
    log_error "Failed to start AppArmor service"
    exit 1
fi

# Check AppArmor status
log_info "Checking AppArmor status..."

if aa-enabled &>/dev/null; then
    log_info "✓ AppArmor is enabled"
else
    log_warn "AppArmor is not fully enabled"
fi

# Display current AppArmor status
log_info "Current AppArmor status:"
aa-status --json 2>/dev/null | grep -E '"profiles"|"processes"' | while IFS= read -r line; do
    log_info "  $line"
done || aa-status 2>/dev/null | head -n 10 | while IFS= read -r line; do
    log_info "  $line"
done

# Count profiles in different modes
ENFORCE_COUNT=$(aa-status 2>/dev/null | grep "profiles are in enforce mode" | grep -oE '[0-9]+' || echo "0")
COMPLAIN_COUNT=$(aa-status 2>/dev/null | grep "profiles are in complain mode" | grep -oE '[0-9]+' || echo "0")
UNCONFINED_COUNT=$(aa-status 2>/dev/null | grep "processes are unconfined" | grep -oE '[0-9]+' || echo "0")

log_info "  Enforce mode: $ENFORCE_COUNT profiles"
log_info "  Complain mode: $COMPLAIN_COUNT profiles"
log_info "  Unconfined: $UNCONFINED_COUNT processes"

# Set profiles to requested mode
log_info "Configuring AppArmor profiles to $APPARMOR_MODE mode..."

if [[ "$APPARMOR_MODE" == "enforce" ]]; then
    # Set all profiles to enforce mode
    if aa-enforce /etc/apparmor.d/* 2>/dev/null; then
        log_info "✓ Profiles set to enforce mode"
        ((PROFILES_CONFIGURED++))
    else
        log_warn "Some profiles could not be set to enforce mode"
    fi
elif [[ "$APPARMOR_MODE" == "complain" ]]; then
    # Set all profiles to complain mode
    if aa-complain /etc/apparmor.d/* 2>/dev/null; then
        log_info "✓ Profiles set to complain mode"
        ((PROFILES_CONFIGURED++))
    else
        log_warn "Some profiles could not be set to complain mode"
    fi
else
    log_error "Invalid mode: $APPARMOR_MODE (use enforce or complain)"
    exit 1
fi

# Reload AppArmor profiles
log_info "Reloading AppArmor profiles..."

if systemctl reload apparmor; then
    log_info "✓ AppArmor profiles reloaded"
    ((PROFILES_CONFIGURED++))
else
    log_warn "Failed to reload some AppArmor profiles"
fi

# List loaded profiles
log_info "Loaded AppArmor profiles:"
aa-status 2>/dev/null | grep -A 100 "profiles are loaded" | grep "^   /" | head -n 20 | while IFS= read -r profile; do
    log_info "  $profile"
done

TOTAL_PROFILES=$(aa-status 2>/dev/null | grep "profiles are loaded" | grep -oE '[0-9]+' || echo "0")
log_info "  ... total: $TOTAL_PROFILES profiles"

# Check for unconfined processes
log_info "Checking for unconfined processes..."

UNCONFINED_PROCS=$(aa-unconfined 2>/dev/null | grep -v "^not confined" | wc -l || echo "0")

if [[ "$UNCONFINED_PROCS" -gt 0 ]]; then
    log_warn "Found $UNCONFINED_PROCS unconfined processes"
    aa-unconfined 2>/dev/null | head -n 10 | while IFS= read -r line; do
        log_info "  $line"
    done
else
    log_info "✓ No unconfined processes detected"
fi

# Configure AppArmor parser cache
log_info "Configuring AppArmor parser cache..."

mkdir -p /var/cache/apparmor
systemctl enable apparmor.service

log_info "✓ Parser cache configured"

# Verify critical profiles
log_info "Verifying critical AppArmor profiles..."

CRITICAL_PROFILES=(
    "/usr/sbin/sshd"
    "/usr/sbin/ntpd"
    "/usr/sbin/chronyd"
    "/usr/bin/man"
)

for profile in "${CRITICAL_PROFILES[@]}"; do
    if aa-status 2>/dev/null | grep -q "$profile"; then
        log_info "  ✓ $profile is protected"
    else
        log_warn "  ✗ $profile is not protected"
    fi
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

NEW_ENFORCE_COUNT=$(aa-status 2>/dev/null | grep "profiles are in enforce mode" | grep -oE '[0-9]+' || echo "0")
NEW_COMPLAIN_COUNT=$(aa-status 2>/dev/null | grep "profiles are in complain mode" | grep -oE '[0-9]+' || echo "0")

log_info "=============================================="
log_info "AppArmor Configuration Summary"
log_info "=============================================="
log_info "AppArmor status: $(aa-enabled &>/dev/null && echo 'enabled' || echo 'disabled')"
log_info "Mode configured: $APPARMOR_MODE"
log_info "Profiles in enforce mode: $NEW_ENFORCE_COUNT"
log_info "Profiles in complain mode: $NEW_COMPLAIN_COUNT"
log_info "Unconfined processes: $UNCONFINED_COUNT"
log_info "Configurations applied: $PROFILES_CONFIGURED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "AppArmor configuration completed!"
log_info ""
log_info "AppArmor commands:"
log_info "  - Status: aa-status"
log_info "  - Enforce profile: aa-enforce /etc/apparmor.d/PROFILE"
log_info "  - Complain profile: aa-complain /etc/apparmor.d/PROFILE"
log_info "  - Disable profile: aa-disable /etc/apparmor.d/PROFILE"
log_info "  - Unconfined: aa-unconfined"