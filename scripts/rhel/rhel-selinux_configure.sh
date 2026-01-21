#!/bin/bash
#===================================================================================
# Script: selinux_configure.sh
# Description: Configure SELinux for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./selinux_configure.sh
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

log_info "Starting SELinux configuration..."

# Configuration variables
SELINUX_CONFIG="/etc/selinux/config"
BACKUP_DIR="/root/selinux_backups"
START_TIME=$(date +%s)

# Desired SELinux mode (enforcing, permissive, disabled)
SELINUX_MODE="${1:-enforcing}"

if [[ ! "$SELINUX_MODE" =~ ^(enforcing|permissive|disabled)$ ]]; then
    log_error "Invalid SELinux mode: $SELINUX_MODE"
    log_error "Valid modes: enforcing, permissive, disabled"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if SELinux is available
if ! command -v getenforce &>/dev/null; then
    log_warn "SELinux tools not installed. Installing..."
    if command -v dnf &>/dev/null; then
        dnf install -y policycoreutils policycoreutils-python-utils selinux-policy selinux-policy-targeted
    elif command -v yum &>/dev/null; then
        yum install -y policycoreutils policycoreutils-python-utils selinux-policy selinux-policy-targeted
    fi
fi

# Get current SELinux status
CURRENT_MODE=$(getenforce 2>/dev/null || echo "Unknown")
CURRENT_CONFIG=$(grep "^SELINUX=" "$SELINUX_CONFIG" | cut -d'=' -f2 || echo "Unknown")

log_info "Current SELinux runtime mode: $CURRENT_MODE"
log_info "Current SELinux config mode: $CURRENT_CONFIG"
log_info "Desired SELinux mode: $SELINUX_MODE"

# Backup current configuration
if [[ -f "$SELINUX_CONFIG" ]]; then
    BACKUP_FILE="$BACKUP_DIR/selinux_config.$(date +%Y%m%d_%H%M%S).bak"
    log_info "Backing up SELinux configuration to: $BACKUP_FILE"
    cp "$SELINUX_CONFIG" "$BACKUP_FILE"
fi

# Update SELinux configuration file
log_info "Updating SELinux configuration file..."
sed -i "s/^SELINUX=.*/SELINUX=$SELINUX_MODE/" "$SELINUX_CONFIG"

# Set SELinux mode for current session (if not disabled)
if [[ "$SELINUX_MODE" != "disabled" ]] && [[ "$CURRENT_MODE" != "Disabled" ]]; then
    log_info "Setting SELinux to $SELINUX_MODE for current session..."
    
    if [[ "$SELINUX_MODE" == "enforcing" ]]; then
        setenforce 1
    elif [[ "$SELINUX_MODE" == "permissive" ]]; then
        setenforce 0
    fi
    
    UPDATED_MODE=$(getenforce)
    log_info "SELinux runtime mode updated to: $UPDATED_MODE"
fi

# Display SELinux status
log_info "SELinux status:"
sestatus | while IFS= read -r line; do
    log_info "  $line"
done

# Check for SELinux denials
log_info "Checking for recent SELinux denials..."
DENIAL_COUNT=$(ausearch -m avc -ts recent 2>/dev/null | grep -c "type=AVC" || echo "0")

if [[ $DENIAL_COUNT -gt 0 ]]; then
    log_warn "Found $DENIAL_COUNT recent SELinux denials"
    log_info "Run 'ausearch -m avc -ts recent' to view denials"
    log_info "Use 'audit2allow' to generate policy modules for denials"
else
    log_info "No recent SELinux denials found"
fi

# Check for context issues
log_info "Checking for file context issues..."
CONTEXT_ISSUES=0

# Check common directories
for dir in /var/www /etc/httpd /usr/share/nginx; do
    if [[ -d "$dir" ]]; then
        if restorecon -n -v "$dir" 2>&1 | grep -q "relabel"; then
            log_warn "Context issues found in: $dir"
            CONTEXT_ISSUES=$((CONTEXT_ISSUES + 1))
        fi
    fi
done

if [[ $CONTEXT_ISSUES -gt 0 ]]; then
    log_warn "Found context issues in $CONTEXT_ISSUES directories"
    log_info "Run 'restorecon -R <directory>' to fix context issues"
else
    log_info "No file context issues detected"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

REBOOT_REQUIRED=false
if [[ "$SELINUX_MODE" == "disabled" ]] && [[ "$CURRENT_MODE" != "Disabled" ]]; then
    REBOOT_REQUIRED=true
elif [[ "$SELINUX_MODE" != "disabled" ]] && [[ "$CURRENT_CONFIG" == "disabled" ]]; then
    REBOOT_REQUIRED=true
fi

log_info "=============================================="
log_info "SELinux Configuration Summary"
log_info "=============================================="
log_info "Previous mode: $CURRENT_CONFIG"
log_info "Configured mode: $SELINUX_MODE"
log_info "Current runtime mode: $(getenforce 2>/dev/null || echo 'N/A')"
log_info "Recent denials: $DENIAL_COUNT"
log_info "Context issues: $CONTEXT_ISSUES"

if [[ "$REBOOT_REQUIRED" == true ]]; then
    log_warn "*** REBOOT REQUIRED ***"
    log_warn "SELinux mode changes require a system reboot"
fi

log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "SELinux configuration completed successfully!"