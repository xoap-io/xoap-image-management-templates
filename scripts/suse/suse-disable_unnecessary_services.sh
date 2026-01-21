#!/bin/bash
#===================================================================================
# Script: disable_unnecessary_services_suse.sh
# Description: Disable unnecessary services on SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./disable_unnecessary_services_suse.sh
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

log_info "Disabling unnecessary services on SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
SERVICES_DISABLED=0
SERVICES_MASKED=0

# List of services to disable
SERVICES_TO_DISABLE=(
    "bluetooth.service"
    "cups.service"
    "cups-browsed.service"
    "avahi-daemon.service"
    "avahi-daemon.socket"
    "ModemManager.service"
    "wpa_supplicant.service"
    "iscsid.service"
    "iscsi.service"
    "rpcbind.service"
    "rpcbind.socket"
    "nfs-client.target"
    "remote-fs.target"
    "postfix.service"
    "sendmail.service"
)

# Services that should be masked (stronger than disable)
SERVICES_TO_MASK=(
    "debug-shell.service"
    "systemd-quotacheck.service"
)

log_info "Services to process:"
log_info "  To disable: ${#SERVICES_TO_DISABLE[@]}"
log_info "  To mask: ${#SERVICES_TO_MASK[@]}"

# Disable services
log_info "Disabling unnecessary services..."

for service in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files | grep -q "^${service}"; then
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log_info "  Disabling $service..."
            
            systemctl stop "$service" 2>/dev/null || log_warn "    Could not stop $service"
            systemctl disable "$service" 2>/dev/null || log_warn "    Could not disable $service"
            
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                log_warn "    ✗ Failed to disable $service"
            else
                log_info "    ✓ Disabled $service"
                ((SERVICES_DISABLED++))
            fi
        else
            log_info "  ○ $service already disabled"
        fi
    else
        log_info "  - $service not installed"
    fi
done

# Mask services
log_info "Masking dangerous services..."

for service in "${SERVICES_TO_MASK[@]}"; do
    if systemctl list-unit-files | grep -q "^${service}"; then
        log_info "  Masking $service..."
        
        systemctl stop "$service" 2>/dev/null || log_warn "    Could not stop $service"
        systemctl mask "$service" 2>/dev/null || log_warn "    Could not mask $service"
        
        if systemctl is-masked --quiet "$service" 2>/dev/null; then
            log_info "    ✓ Masked $service"
            ((SERVICES_MASKED++))
        else
            log_warn "    ✗ Failed to mask $service"
        fi
    else
        log_info "  - $service not installed"
    fi
done

# Verify essential services are still running
log_info "Verifying essential services..."

ESSENTIAL_SERVICES=(
    "sshd.service"
    "systemd-journald.service"
    "dbus.service"
)

for service in "${ESSENTIAL_SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        log_info "  ✓ $service is running"
    else
        log_warn "  ✗ $service is not running"
    fi
done

# Display currently enabled services
log_info "Currently enabled services:"
systemctl list-unit-files --state=enabled --no-pager | grep ".service" | head -n 20 | while IFS= read -r line; do
    log_info "  $line"
done

ENABLED_COUNT=$(systemctl list-unit-files --state=enabled --no-pager | grep -c ".service" || echo "0")
log_info "  Total enabled services: $ENABLED_COUNT"

# Display masked services
log_info "Masked services:"
systemctl list-unit-files --state=masked --no-pager | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Service Disabling Summary"
log_info "=============================================="
log_info "Services disabled: $SERVICES_DISABLED"
log_info "Services masked: $SERVICES_MASKED"
log_info "Total enabled services: $ENABLED_COUNT"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Service disabling completed!"
log_info ""
log_info "To re-enable a service:"
log_info "  systemctl unmask SERVICE"
log_info "  systemctl enable SERVICE"
log_info "  systemctl start SERVICE"