#!/bin/bash
#===================================================================================
# Script: firewalld_hardening.sh
# Description: Configure and harden firewalld for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./firewalld_hardening.sh
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

log_info "Starting firewalld hardening..."

# Statistics tracking
START_TIME=$(date +%s)
RULES_ADDED=0

# Check if firewalld is installed
if ! command -v firewall-cmd &>/dev/null; then
    log_warn "firewalld is not installed. Installing..."
    if command -v dnf &>/dev/null; then
        dnf install -y firewalld
    elif command -v yum &>/dev/null; then
        yum install -y firewalld
    else
        log_error "Cannot install firewalld - no package manager found"
        exit 1
    fi
fi

# Start and enable firewalld
log_info "Ensuring firewalld is enabled and running..."
systemctl enable firewalld
systemctl start firewalld

# Wait for firewalld to be ready
sleep 2

# Backup current configuration
BACKUP_DIR="/root/firewalld_backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/firewalld_config.$(date +%Y%m%d_%H%M%S).txt"

log_info "Backing up current firewall rules to: $BACKUP_FILE"
firewall-cmd --list-all-zones > "$BACKUP_FILE" 2>/dev/null || echo "No previous configuration" > "$BACKUP_FILE"

# Set default zone to public
log_info "Setting default zone to 'public'..."
firewall-cmd --set-default-zone=public

# Configure default deny policy
log_info "Configuring restrictive firewall policy..."

# Remove all services from public zone first
log_info "Removing default services from public zone..."
for service in $(firewall-cmd --zone=public --list-services); do
    log_info "Removing service: $service"
    firewall-cmd --zone=public --remove-service="$service" --permanent
done

# Add SSH service (critical for remote access)
log_info "Allowing SSH service..."
if firewall-cmd --zone=public --add-service=ssh --permanent; then
    RULES_ADDED=$((RULES_ADDED + 1))
    log_info "SSH service allowed"
else
    log_error "Failed to add SSH service"
    exit 1
fi

# Optional: Add other common services (uncomment as needed)
# log_info "Allowing HTTP service..."
# firewall-cmd --zone=public --add-service=http --permanent
# RULES_ADDED=$((RULES_ADDED + 1))

# log_info "Allowing HTTPS service..."
# firewall-cmd --zone=public --add-service=https --permanent
# RULES_ADDED=$((RULES_ADDED + 1))

# Apply rate limiting to SSH (protection against brute force)
log_info "Applying rate limiting to SSH..."
firewall-cmd --permanent --add-rich-rule='rule service name="ssh" limit value="10/m" accept'
RULES_ADDED=$((RULES_ADDED + 1))

# Block common attack ports
log_info "Blocking common attack ports..."

# Block NetBIOS
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" port port=137 protocol=tcp reject'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" port port=138 protocol=tcp reject'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" port port=139 protocol=tcp reject'
RULES_ADDED=$((RULES_ADDED + 3))

# Enable logging for denied packets
log_info "Enabling logging for denied packets..."
firewall-cmd --set-log-denied=all --permanent

# Reload firewalld to apply all changes
log_info "Reloading firewalld configuration..."
firewall-cmd --reload

# Verify firewalld status
log_info "Verifying firewalld status..."
FIREWALLD_STATUS=$(systemctl is-active firewalld)

if [[ "$FIREWALLD_STATUS" == "active" ]]; then
    log_info "Firewalld is active and enabled"
else
    log_error "Firewalld is not active"
    exit 1
fi

# Display current configuration
log_info "Current firewall configuration (public zone):"
firewall-cmd --zone=public --list-all | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Firewalld Hardening Summary"
log_info "=============================================="
log_info "Firewall status: $FIREWALLD_STATUS"
log_info "Rules configured: $RULES_ADDED"
log_info "Default zone: $(firewall-cmd --get-default-zone)"
log_info "Backup saved to: $BACKUP_FILE"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Firewalld hardening completed successfully!"
log_info ""
log_info "NOTE: To allow additional services, use:"
log_info "  firewall-cmd --zone=public --add-service=<service> --permanent"
log_info "  firewall-cmd --reload"