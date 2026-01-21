#!/bin/bash
#===================================================================================
# Script: zypper-locks_suse.sh
# Description: Remove zypper package locks to avoid dependency conflicts on SUSE Linux
# Author: XOAP Infrastructure Team
# Usage: ./zypper-locks_suse.sh
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

log_info "Starting zypper lock removal..."

# Statistics tracking
START_TIME=$(date +%s)

# Check if zypper is available
if ! command -v zypper &>/dev/null; then
    log_error "zypper command not found - not a SUSE-based system?"
    exit 1
fi

# List current locks before removal
log_info "Checking for existing package locks..."
LOCKS_BEFORE=$(zypper --non-interactive locks 2>/dev/null | grep -c "^[0-9]" || echo "0")

if [[ $LOCKS_BEFORE -eq 0 ]]; then
    log_info "No package locks found"
else
    log_info "Found $LOCKS_BEFORE package lock(s)"
    log_info "Current locks:"
    zypper --non-interactive locks | tail -n +3 | while IFS= read -r line; do
        log_info "  $line"
    done
fi

# Remove all package locks
log_info "Removing all package locks..."
if zypper --non-interactive remove-lock '*' 2>&1 | tee -a /tmp/zypper-locks-removal.log; then
    log_info "Package locks removal command completed"
else
    log_warn "Package lock removal completed with warnings"
fi

# Verify locks were removed
log_info "Verifying lock removal..."
LOCKS_AFTER=$(zypper --non-interactive locks 2>/dev/null | grep -c "^[0-9]" || echo "0")

if [[ $LOCKS_AFTER -eq 0 ]]; then
    log_info "All package locks successfully removed"
    LOCKS_REMOVED=$LOCKS_BEFORE
else
    log_warn "Some locks may still remain: $LOCKS_AFTER lock(s)"
    LOCKS_REMOVED=$((LOCKS_BEFORE - LOCKS_AFTER))
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Zypper Lock Removal Summary"
log_info "=============================================="
log_info "Locks before: $LOCKS_BEFORE"
log_info "Locks after: $LOCKS_AFTER"
log_info "Locks removed: $LOCKS_REMOVED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Zypper lock removal completed successfully!"
