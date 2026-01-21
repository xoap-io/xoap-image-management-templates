#!/bin/bash
#===================================================================================
# Script: unregister_suse.sh
# Description: Unregister SUSE system from SUSE Customer Center
# Author: XOAP Infrastructure Team
# Usage: ./unregister_suse.sh
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

log_info "Starting SUSE unregistration..."

# Statistics tracking
START_TIME=$(date +%s)
CLEANUP_ITEMS=0

# Check if SUSEConnect is available
if ! command -v SUSEConnect &>/dev/null; then
    log_warn "SUSEConnect is not installed"
    log_info "Nothing to unregister"
    exit 0
fi

# Check current registration status
log_info "Checking current registration status..."

if SUSEConnect --status &>/dev/null; then
    log_info "System is currently registered"
    
    SUSEConnect --status-text | while IFS= read -r line; do
        log_info "  $line"
    done
else
    log_info "System is not currently registered"
    log_info "Will clean up any leftover configuration..."
fi

# Deactivate all products/modules first
log_info "Deactivating all products and modules..."

ACTIVE_PRODUCTS=$(SUSEConnect --list --installed 2>/dev/null | grep "Identifier:" | awk '{print $2}' || echo "")

if [[ -n "$ACTIVE_PRODUCTS" ]]; then
    while IFS= read -r product; do
        if [[ -n "$product" ]] && [[ "$product" != "SLES" ]]; then
            log_info "  Deactivating product: $product"
            SUSEConnect -d -p "$product" 2>/dev/null || log_warn "Failed to deactivate $product"
            ((CLEANUP_ITEMS++))
        fi
    done <<< "$ACTIVE_PRODUCTS"
fi

# Unregister from SCC
log_info "Unregistering from SUSE Customer Center..."

if SUSEConnect --de-register 2>&1 | tee /tmp/suse-unregister.log; then
    log_info "✓ System unregistered successfully"
    ((CLEANUP_ITEMS++))
else
    log_warn "Failed to unregister (may already be unregistered)"
fi

# Clean up registration files
log_info "Cleaning up registration files..."

CLEANUP_FILES=(
    "/etc/SUSEConnect"
    "/etc/zypp/credentials.d/SCCcredentials"
    "/var/cache/SUSEConnect"
)

for file in "${CLEANUP_FILES[@]}"; do
    if [[ -e "$file" ]]; then
        log_info "  Removing: $file"
        rm -rf "$file"
        ((CLEANUP_ITEMS++))
    fi
done

# Remove SCC repositories
log_info "Removing SCC repositories..."

SCC_REPOS=$(zypper repos | grep -i "scc\|suse" | awk '{print $3}' || echo "")

if [[ -n "$SCC_REPOS" ]]; then
    while IFS= read -r repo; do
        if [[ -n "$repo" ]]; then
            log_info "  Removing repository: $repo"
            zypper removerepo "$repo" 2>/dev/null || log_warn "Failed to remove $repo"
            ((CLEANUP_ITEMS++))
        fi
    done <<< "$SCC_REPOS"
fi

# Clean zypper cache
log_info "Cleaning package manager cache..."

zypper clean --all &>/dev/null || log_warn "Failed to clean zypper cache"
((CLEANUP_ITEMS++))

# Verify unregistration
log_info "Verifying unregistration..."

if SUSEConnect --status &>/dev/null; then
    log_warn "System still appears to be registered"
    SUSEConnect --status-text | while IFS= read -r line; do
        log_warn "  $line"
    done
else
    log_info "✓ System is no longer registered"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "SUSE Unregistration Summary"
log_info "=============================================="
log_info "Cleanup items processed: $CLEANUP_ITEMS"
log_info "Registration status: $(SUSEConnect --status &>/dev/null && echo 'still registered' || echo 'unregistered')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "SUSE unregistration completed!"
log_info ""
log_info "Important notes:"
log_info "  - System is now unregistered from SCC"
log_info "  - No SUSE repositories are available"
log_info "  - This is normal for image templates"
log_info "  - Re-register after deployment if needed"