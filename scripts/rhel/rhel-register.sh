#!/bin/bash
#===================================================================================
# Script: register_rhel.sh
# Description: Register RHEL system with Red Hat Subscription Management
# Author: XOAP Infrastructure Team
# Usage: ./register_rhel.sh [--username USERNAME] [--password PASSWORD] [--org ORG] [--activation-key KEY]
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
RHSM_USERNAME="${RHSM_USERNAME:-}"
RHSM_PASSWORD="${RHSM_PASSWORD:-}"
RHSM_ORG="${RHSM_ORG:-}"
RHSM_ACTIVATION_KEY="${RHSM_ACTIVATION_KEY:-}"
AUTO_ATTACH="${AUTO_ATTACH:-true}"
FORCE_REGISTER="${FORCE_REGISTER:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --username)
            RHSM_USERNAME="$2"
            shift 2
            ;;
        --password)
            RHSM_PASSWORD="$2"
            shift 2
            ;;
        --org)
            RHSM_ORG="$2"
            shift 2
            ;;
        --activation-key)
            RHSM_ACTIVATION_KEY="$2"
            shift 2
            ;;
        --no-auto-attach)
            AUTO_ATTACH="false"
            shift
            ;;
        --force)
            FORCE_REGISTER="true"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting RHEL registration process..."

# Statistics tracking
START_TIME=$(date +%s)
REPOS_ENABLED=0

# Check if this is actually RHEL
if ! grep -qi "Red Hat Enterprise Linux" /etc/redhat-release 2>/dev/null; then
    log_warn "This does not appear to be Red Hat Enterprise Linux"
    log_info "System: $(cat /etc/redhat-release 2>/dev/null || echo 'Unknown')"
    log_warn "Registration may not work as expected"
fi

# Check if subscription-manager is installed
if ! command -v subscription-manager &>/dev/null; then
    log_error "subscription-manager is not installed"
    exit 1
fi

# Check current registration status
log_info "Checking current registration status..."

if subscription-manager status &>/dev/null; then
    CURRENTLY_REGISTERED=true
    log_info "System is currently registered"
    
    if [[ "$FORCE_REGISTER" != "true" ]]; then
        log_info "Use --force to re-register"
        
        # Display current subscription info
        log_info "Current subscription status:"
        subscription-manager status | while IFS= read -r line; do
            log_info "  $line"
        done
        
        exit 0
    else
        log_info "Force registration requested, unregistering first..."
        subscription-manager unregister || log_warn "Failed to unregister (continuing anyway)"
        CURRENTLY_REGISTERED=false
    fi
else
    CURRENTLY_REGISTERED=false
    log_info "System is not currently registered"
fi

# Validate authentication method
if [[ -n "$RHSM_ACTIVATION_KEY" ]] && [[ -n "$RHSM_ORG" ]]; then
    AUTH_METHOD="activation-key"
    log_info "Using activation key authentication"
elif [[ -n "$RHSM_USERNAME" ]] && [[ -n "$RHSM_PASSWORD" ]]; then
    AUTH_METHOD="username-password"
    log_info "Using username/password authentication"
else
    log_error "Must provide either:"
    log_error "  1. --org and --activation-key"
    log_error "  2. --username and --password"
    log_error "Or set environment variables: RHSM_ORG, RHSM_ACTIVATION_KEY or RHSM_USERNAME, RHSM_PASSWORD"
    exit 1
fi

# Clean up any leftover certificates
log_info "Cleaning up any leftover certificates..."
subscription-manager clean || log_warn "Failed to clean certificates"

# Register the system
log_info "Registering system with Red Hat Subscription Management..."

REGISTER_CMD="subscription-manager register"

if [[ "$AUTH_METHOD" == "activation-key" ]]; then
    REGISTER_CMD="$REGISTER_CMD --org='$RHSM_ORG' --activationkey='$RHSM_ACTIVATION_KEY'"
else
    REGISTER_CMD="$REGISTER_CMD --username='$RHSM_USERNAME' --password='REDACTED'"
fi

log_info "Executing: ${REGISTER_CMD}"

if [[ "$AUTH_METHOD" == "activation-key" ]]; then
    if subscription-manager register --org="$RHSM_ORG" --activationkey="$RHSM_ACTIVATION_KEY"; then
        log_info "✓ System registered successfully"
    else
        log_error "✗ Registration failed"
        exit 1
    fi
else
    if subscription-manager register --username="$RHSM_USERNAME" --password="$RHSM_PASSWORD" ${AUTO_ATTACH:+--auto-attach}; then
        log_info "✓ System registered successfully"
    else
        log_error "✗ Registration failed"
        exit 1
    fi
fi

# Attach subscription (if not using activation key with auto-attach)
if [[ "$AUTH_METHOD" == "username-password" ]] && [[ "$AUTO_ATTACH" == "true" ]]; then
    log_info "Auto-attaching subscription..."
    
    if subscription-manager attach --auto; then
        log_info "✓ Subscription attached successfully"
    else
        log_warn "✗ Failed to auto-attach subscription"
        log_info "You may need to manually attach a subscription"
    fi
fi

# Refresh subscription data
log_info "Refreshing subscription data..."
subscription-manager refresh || log_warn "Failed to refresh subscription data"

# Enable recommended repositories
log_info "Checking enabled repositories..."

ENABLED_REPOS=$(subscription-manager repos --list-enabled 2>/dev/null | grep "Repo ID:" | wc -l || echo "0")
log_info "Currently enabled repositories: $ENABLED_REPOS"

# Display subscription status
log_info "Subscription status:"
subscription-manager status | while IFS= read -r line; do
    log_info "  $line"
done

# Display available subscriptions
log_info "Available subscriptions:"
subscription-manager list --available --matches='*' 2>/dev/null | head -n 20 | while IFS= read -r line; do
    log_info "  $line"
done

# Display consumed subscriptions
log_info "Consumed subscriptions:"
subscription-manager list --consumed 2>/dev/null | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "RHEL Registration Summary"
log_info "=============================================="
log_info "Authentication method: $AUTH_METHOD"
log_info "Registration status: $(subscription-manager status --format=json 2>/dev/null | grep -o '"status": "[^"]*"' | cut -d'"' -f4 || echo 'registered')"
log_info "Enabled repositories: $ENABLED_REPOS"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "RHEL registration completed!"
log_info ""
log_info "Next steps:"
log_info "  1. Verify enabled repositories: subscription-manager repos --list-enabled"
log_info "  2. Enable additional repos: subscription-manager repos --enable=<repo-id>"
log_info "  3. Update system: dnf update -y"