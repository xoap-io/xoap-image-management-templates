#!/bin/bash
#===================================================================================
# Script: unregister_rhel.sh
# Description: Unregister RHEL system from Red Hat Subscription Management
# Author: XOAP Infrastructure Team
# Usage: ./unregister_rhel.sh
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

log_info "Starting RHEL unregistration process..."

# Statistics tracking
START_TIME=$(date +%s)
CLEANUP_ITEMS=0

# Check if subscription-manager is installed
if ! command -v subscription-manager &>/dev/null; then
    log_warn "subscription-manager is not installed"
    log_info "Nothing to unregister"
    exit 0
fi

# Check current registration status
log_info "Checking current registration status..."

if subscription-manager status &>/dev/null; then
    log_info "System is currently registered"
    
    # Display current subscription info before unregistering
    log_info "Current subscription status:"
    subscription-manager status | while IFS= read -r line; do
        log_info "  $line"
    done
    
    # List consumed subscriptions
    log_info "Consumed subscriptions:"
    subscription-manager list --consumed 2>/dev/null | while IFS= read -r line; do
        log_info "  $line"
    done
else
    log_info "System is not currently registered"
    log_info "Will clean up any leftover configuration..."
fi

# Remove all subscriptions
log_info "Removing all subscriptions..."

if subscription-manager remove --all 2>/dev/null; then
    log_info "✓ All subscriptions removed"
    ((CLEANUP_ITEMS++))
else
    log_warn "Failed to remove subscriptions (may not be attached)"
fi

# Unregister from RHSM
log_info "Unregistering from Red Hat Subscription Management..."

if subscription-manager unregister 2>/dev/null; then
    log_info "✓ System unregistered successfully"
    ((CLEANUP_ITEMS++))
else
    log_warn "Failed to unregister (may already be unregistered)"
fi

# Clean up subscription data
log_info "Cleaning up subscription data..."

if subscription-manager clean; then
    log_info "✓ Subscription data cleaned"
    ((CLEANUP_ITEMS++))
else
    log_warn "Failed to clean subscription data"
fi

# Remove consumer certificate
if [[ -f /etc/pki/consumer/cert.pem ]]; then
    log_info "Removing consumer certificate..."
    rm -f /etc/pki/consumer/cert.pem
    ((CLEANUP_ITEMS++))
fi

if [[ -f /etc/pki/consumer/key.pem ]]; then
    log_info "Removing consumer key..."
    rm -f /etc/pki/consumer/key.pem
    ((CLEANUP_ITEMS++))
fi

# Remove entitlement certificates
if [[ -d /etc/pki/entitlement ]]; then
    ENTITLEMENT_COUNT=$(find /etc/pki/entitlement -type f -name "*.pem" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$ENTITLEMENT_COUNT" -gt 0 ]]; then
        log_info "Removing $ENTITLEMENT_COUNT entitlement certificate(s)..."
        find /etc/pki/entitlement -type f -name "*.pem" -delete
        ((CLEANUP_ITEMS++))
    fi
fi

# Remove redhat.repo backup if exists
if [[ -f /etc/yum.repos.d/redhat.repo ]]; then
    log_info "Backing up redhat.repo..."
    mv /etc/yum.repos.d/redhat.repo /etc/yum.repos.d/redhat.repo.unregistered.$(date +%Y%m%d-%H%M%S)
    ((CLEANUP_ITEMS++))
fi

# Clean YUM/DNF cache
log_info "Cleaning package manager cache..."

if command -v dnf &>/dev/null; then
    dnf clean all &>/dev/null || log_warn "Failed to clean DNF cache"
elif command -v yum &>/dev/null; then
    yum clean all &>/dev/null || log_warn "Failed to clean YUM cache"
fi

((CLEANUP_ITEMS++))

# Remove rhsm.log (optional - uncomment if desired)
# if [[ -f /var/log/rhsm/rhsm.log ]]; then
#     log_info "Removing RHSM log file..."
#     rm -f /var/log/rhsm/rhsm.log
#     ((CLEANUP_ITEMS++))
# fi

# Verify unregistration
log_info "Verifying unregistration..."

if subscription-manager status &>/dev/null; then
    log_warn "System still appears to be registered"
    subscription-manager status | while IFS= read -r line; do
        log_warn "  $line"
    done
else
    log_info "✓ System is no longer registered"
fi

# Check for remaining certificates
REMAINING_CERTS=$(find /etc/pki/consumer /etc/pki/entitlement -type f -name "*.pem" 2>/dev/null | wc -l || echo "0")

if [[ "$REMAINING_CERTS" -gt 0 ]]; then
    log_warn "Found $REMAINING_CERTS remaining certificate(s)"
    find /etc/pki/consumer /etc/pki/entitlement -type f -name "*.pem" 2>/dev/null | while IFS= read -r cert; do
        log_warn "  $cert"
    done
else
    log_info "✓ No remaining certificates found"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "RHEL Unregistration Summary"
log_info "=============================================="
log_info "Cleanup items processed: $CLEANUP_ITEMS"
log_info "Remaining certificates: $REMAINING_CERTS"
log_info "Registration status: $(subscription-manager status &>/dev/null && echo 'still registered' || echo 'unregistered')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "RHEL unregistration completed!"
log_info ""
log_info "Important notes:"
log_info "  - System is now unregistered from RHSM"
log_info "  - No Red Hat repositories are available"
log_info "  - This is normal for image templates"
log_info "  - Re-register after deployment if needed"