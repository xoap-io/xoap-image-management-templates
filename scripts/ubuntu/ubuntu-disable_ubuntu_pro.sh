#!/bin/bash
#===================================================================================
# Script: ubuntu-disable_ubuntu_pro.sh
# Description: Disable Ubuntu Pro for image templates
# Author: XOAP Infrastructure Team
# Usage: ./ubuntu-disable_ubuntu_pro.sh
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

log_info "Disabling Ubuntu Pro for image templates..."

# Statistics tracking
START_TIME=$(date +%s)
ACTIONS_PERFORMED=0

# Check if ubuntu-advantage-tools is installed
if ! command -v pro &>/dev/null; then
    log_info "Ubuntu Pro client is not installed, nothing to disable"
    exit 0
fi

# Get current status
log_info "Checking current Ubuntu Pro status..."

ATTACHED=$(pro status 2>/dev/null | grep -q "This machine is attached" && echo "yes" || echo "no")

if [[ "$ATTACHED" == "yes" ]]; then
    log_info "Machine is currently attached to Ubuntu Pro"
    
    # List enabled services
    log_info "Currently enabled services:"
    pro status 2>/dev/null | grep "enabled" | while IFS= read -r line; do
        log_info "  $line"
    done
    
    # Detach from Ubuntu Pro
    log_info "Detaching from Ubuntu Pro subscription..."
    
    if pro detach --assume-yes; then
        log_info "✓ Successfully detached from Ubuntu Pro"
        ((ACTIONS_PERFORMED++))
    else
        log_error "Failed to detach from Ubuntu Pro"
        exit 1
    fi
else
    log_info "Machine is not attached to Ubuntu Pro"
fi

# Remove Ubuntu Pro machine ID and state files
log_info "Cleaning Ubuntu Pro machine state..."

PRO_STATE_FILES=(
    "/var/lib/ubuntu-advantage/machine-id"
    "/var/lib/ubuntu-advantage/private/machine-token.json"
    "/var/lib/ubuntu-advantage/private/user-config.json"
    "/var/lib/ubuntu-advantage/jobs-status.json"
)

for file in "${PRO_STATE_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log_info "  ✓ Removed $file"
        ((ACTIONS_PERFORMED++))
    fi
done

# Clean Pro caches
log_info "Cleaning Ubuntu Pro caches..."

PRO_CACHE_DIRS=(
    "/var/cache/ubuntu-advantage-tools"
    "/var/lib/ubuntu-advantage/messages"
)

for dir in "${PRO_CACHE_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        rm -rf "${dir:?}"/*
        log_info "  ✓ Cleaned $dir"
        ((ACTIONS_PERFORMED++))
    fi
done

# Disable Pro services in apt sources
log_info "Disabling Ubuntu Pro apt repositories..."

PRO_SOURCES_DIR="/etc/apt/sources.list.d"

if [[ -d "$PRO_SOURCES_DIR" ]]; then
    find "$PRO_SOURCES_DIR" -name "ubuntu-*-esm-*.list" -type f | while read -r file; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "  ✓ Removed $(basename "$file")"
            ((ACTIONS_PERFORMED++))
        fi
    done
fi

# Remove Pro apt auth configuration
log_info "Removing Ubuntu Pro apt authentication..."

PRO_AUTH_FILE="/etc/apt/auth.conf.d/90ubuntu-advantage"

if [[ -f "$PRO_AUTH_FILE" ]]; then
    rm -f "$PRO_AUTH_FILE"
    log_info "  ✓ Removed apt authentication file"
    ((ACTIONS_PERFORMED++))
fi

# Disable Pro timer services
log_info "Disabling Ubuntu Pro timer services..."

PRO_TIMERS=(
    "ua-timer.timer"
    "ubuntu-advantage.timer"
)

for timer in "${PRO_TIMERS[@]}"; do
    if systemctl is-enabled --quiet "$timer" 2>/dev/null; then
        systemctl disable --quiet "$timer" 2>/dev/null || true
        systemctl stop "$timer" 2>/dev/null || true
        log_info "  ✓ Disabled $timer"
        ((ACTIONS_PERFORMED++))
    fi
done

# Update apt cache
log_info "Updating apt package cache..."

if apt-get update -qq 2>&1 | tee /tmp/apt_update_pro_disable.log >/dev/null; then
    log_info "✓ Package cache updated"
    ((ACTIONS_PERFORMED++))
else
    log_warn "Package cache update reported warnings"
fi

# Verify Pro is disabled
log_info "Verifying Ubuntu Pro status..."

FINAL_STATUS=$(pro status 2>/dev/null | grep -q "This machine is NOT attached" && echo "not attached" || echo "status unclear")

log_info "Final status: $FINAL_STATUS"

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info ""
log_info "=============================================="
log_info "Ubuntu Pro Disable Summary"
log_info "=============================================="
log_info "Initial status: $ATTACHED"
log_info "Final status: $FINAL_STATUS"
log_info "Actions performed: $ACTIONS_PERFORMED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="

if [[ "$FINAL_STATUS" == "not attached" ]]; then
    log_info "✓ Ubuntu Pro successfully disabled for image template"
    log_info ""
    log_info "Image is now clean and ready for cloning/distribution"
else
    log_warn "Ubuntu Pro status is unclear, manual verification recommended"
fi