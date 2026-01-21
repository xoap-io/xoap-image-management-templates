#!/bin/bash
#===================================================================================
# Script: register_suse.sh
# Description: Register SUSE system with SUSE Customer Center
# Author: XOAP Infrastructure Team
# Usage: ./register_suse.sh [--email EMAIL] [--regcode CODE]
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
SUSE_EMAIL="${SUSE_EMAIL:-}"
SUSE_REGCODE="${SUSE_REGCODE:-}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            SUSE_EMAIL="$2"
            shift 2
            ;;
        --regcode)
            SUSE_REGCODE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting SUSE registration..."

# Statistics tracking
START_TIME=$(date +%s)

# Check if this is SLES
if ! grep -qi "SUSE Linux Enterprise" /etc/os-release 2>/dev/null; then
    log_warn "This does not appear to be SUSE Linux Enterprise"
    log_info "System: $(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME=" | cut -d'"' -f2 || echo 'Unknown')"
    log_warn "Registration may not work as expected"
fi

# Check if SUSEConnect is available
if ! command -v SUSEConnect &>/dev/null; then
    log_error "SUSEConnect is not installed"
    exit 1
fi

# Check current registration status
log_info "Checking current registration status..."

if SUSEConnect --status &>/dev/null; then
    log_info "System is currently registered"
    
    SUSEConnect --status-text | while IFS= read -r line; do
        log_info "  $line"
    done
    
    log_info "Use --force if you want to re-register"
    exit 0
else
    log_info "System is not currently registered"
fi

# Validate registration code
if [[ -z "$SUSE_REGCODE" ]]; then
    log_error "Registration code required"
    log_error "Use: --regcode CODE"
    log_error "Or set: SUSE_REGCODE environment variable"
    exit 1
fi

# Register the system
log_info "Registering system with SUSE Customer Center..."

REGISTER_CMD="SUSEConnect -r $SUSE_REGCODE"

if [[ -n "$SUSE_EMAIL" ]]; then
    REGISTER_CMD="$REGISTER_CMD -e $SUSE_EMAIL"
    log_info "Using email: $SUSE_EMAIL"
fi

log_info "Executing registration..."

if $REGISTER_CMD 2>&1 | tee /tmp/suse-register.log; then
    log_info "✓ System registered successfully"
else
    log_error "✗ Registration failed"
    cat /tmp/suse-register.log
    exit 1
fi

# Display registration status
log_info "Registration status:"
SUSEConnect --status-text | while IFS= read -r line; do
    log_info "  $line"
done

# List available modules
log_info "Available modules and extensions:"
SUSEConnect --list-extensions | while IFS= read -r line; do
    log_info "  $line"
done

# Refresh repositories
log_info "Refreshing package repositories..."
zypper refresh

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

REGISTERED_PRODUCTS=$(SUSEConnect --status-text 2>/dev/null | grep -c "Registered" || echo "0")

log_info "=============================================="
log_info "SUSE Registration Summary"
log_info "=============================================="
log_info "Registration status: $(SUSEConnect --status &>/dev/null && echo 'registered' || echo 'not registered')"
log_info "Registered products: $REGISTERED_PRODUCTS"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "SUSE registration completed!"
log_info ""
log_info "Next steps:"
log_info "  - List extensions: SUSEConnect --list-extensions"
log_info "  - Activate module: SUSEConnect -p <product>"
log_info "  - Update system: zypper update"