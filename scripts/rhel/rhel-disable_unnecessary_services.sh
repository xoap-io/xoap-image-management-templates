#!/bin/bash
#===================================================================================
# Script: disable_unnecessary_services.sh
# Description: Disable unnecessary systemd services for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./disable_unnecessary_services.sh
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

log_info "Starting service disable process..."

# Statistics tracking
START_TIME=$(date +%s)
SERVICES_DISABLED=0
SERVICES_STOPPED=0
SERVICES_NOT_FOUND=0

# List of services to disable (commonly unneeded in VM templates)
SERVICES_TO_DISABLE=(
    "cups.service"
    "cups.socket"
    "cups.path"
    "avahi-daemon.service"
    "avahi-daemon.socket"
    "bluetooth.service"
    "iscsid.service"
    "iscsi.service"
    "lvm2-monitor.service"
    "multipathd.service"
    "mdmonitor.service"
    "rpcbind.service"
    "rpcbind.socket"
    "nfs-client.target"
    "remote-fs.target"
    "postfix.service"
    "kdump.service"
)

# Function to disable and stop a service
disable_service() {
    local service="$1"
    
    # Check if service exists
    if ! systemctl list-unit-files "$service" &>/dev/null; then
        log_warn "Service not found: $service"
        SERVICES_NOT_FOUND=$((SERVICES_NOT_FOUND + 1))
        return
    fi
    
    # Check if service is loaded
    if ! systemctl is-enabled "$service" &>/dev/null; then
        log_info "Service already disabled or non-existent: $service"
        return
    fi
    
    # Stop the service if running
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_info "Stopping service: $service"
        if systemctl stop "$service" 2>/dev/null; then
            SERVICES_STOPPED=$((SERVICES_STOPPED + 1))
            log_info "Successfully stopped: $service"
        else
            log_warn "Failed to stop: $service (may not be critical)"
        fi
    fi
    
    # Disable the service
    log_info "Disabling service: $service"
    if systemctl disable "$service" 2>/dev/null; then
        SERVICES_DISABLED=$((SERVICES_DISABLED + 1))
        log_info "Successfully disabled: $service"
    else
        log_warn "Failed to disable: $service (may already be disabled)"
    fi
    
    # Mask service to prevent activation
    if systemctl mask "$service" 2>/dev/null; then
        log_info "Masked service: $service"
    fi
}

# Disable each service
log_info "Processing ${#SERVICES_TO_DISABLE[@]} services..."
for service in "${SERVICES_TO_DISABLE[@]}"; do
    disable_service "$service"
done

# Reload systemd daemon
log_info "Reloading systemd daemon..."
systemctl daemon-reload

# Verify disabled services
log_info "Verifying disabled services..."
VERIFICATION_FAILED=0
for service in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        log_warn "Service still enabled: $service"
        VERIFICATION_FAILED=$((VERIFICATION_FAILED + 1))
    fi
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Service Disable Summary"
log_info "=============================================="
log_info "Total services processed: ${#SERVICES_TO_DISABLE[@]}"
log_info "Services stopped: $SERVICES_STOPPED"
log_info "Services disabled: $SERVICES_DISABLED"
log_info "Services not found: $SERVICES_NOT_FOUND"
if [[ $VERIFICATION_FAILED -gt 0 ]]; then
    log_warn "Verification failures: $VERIFICATION_FAILED"
else
    log_info "All services verified as disabled"
fi
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Service disable completed successfully!"