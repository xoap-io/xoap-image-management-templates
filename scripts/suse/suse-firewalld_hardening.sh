#!/bin/bash
#===================================================================================
# Script: firewalld_hardening_suse.sh
# Description: Configure and harden firewall for SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./firewalld_hardening_suse.sh [--ssh-port PORT]
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
SSH_PORT="${SSH_PORT:-22}"
DEFAULT_ZONE="${DEFAULT_ZONE:-public}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --zone)
            DEFAULT_ZONE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting firewall hardening for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
RULES_CONFIGURED=0

# Install firewalld if not present
if ! command -v firewall-cmd &>/dev/null; then
    log_info "Installing firewalld..."
    
    if zypper install -y firewalld; then
        log_info "✓ firewalld installed"
        ((RULES_CONFIGURED++))
    else
        log_error "Failed to install firewalld"
        exit 1
    fi
else
    log_info "firewalld is already installed"
fi

# Enable and start firewalld
log_info "Enabling firewalld service..."

systemctl enable firewalld
systemctl start firewalld

# Wait for firewalld to be ready
sleep 2

if systemctl is-active --quiet firewalld; then
    log_info "✓ firewalld is running"
else
    log_error "Failed to start firewalld"
    exit 1
fi

# Set default zone
log_info "Setting default zone to: $DEFAULT_ZONE"

firewall-cmd --set-default-zone="$DEFAULT_ZONE"
log_info "✓ Default zone set"
((RULES_CONFIGURED++))

# Configure default zone (public)
log_info "Configuring $DEFAULT_ZONE zone..."

# Remove all services first
for service in $(firewall-cmd --zone="$DEFAULT_ZONE" --list-services); do
    firewall-cmd --zone="$DEFAULT_ZONE" --remove-service="$service" --permanent
    log_info "  Removed service: $service"
done

# Add SSH with rate limiting
log_info "Adding SSH service on port $SSH_PORT with rate limiting..."

if [[ "$SSH_PORT" != "22" ]]; then
    # Remove default SSH service
    firewall-cmd --zone="$DEFAULT_ZONE" --remove-service=ssh --permanent 2>/dev/null || true
    
    # Add custom SSH port
    firewall-cmd --zone="$DEFAULT_ZONE" --add-port="${SSH_PORT}/tcp" --permanent
    log_info "  ✓ Custom SSH port $SSH_PORT added"
else
    firewall-cmd --zone="$DEFAULT_ZONE" --add-service=ssh --permanent
    log_info "  ✓ SSH service added"
fi

((RULES_CONFIGURED++))

# Add SSH rate limiting using rich rules
firewall-cmd --zone="$DEFAULT_ZONE" --add-rich-rule='rule service name="ssh" limit value="10/m" accept' --permanent 2>/dev/null || \
    log_warn "Could not add SSH rate limiting rule"

log_info "✓ SSH rate limiting configured"
((RULES_CONFIGURED++))

# Drop invalid packets
firewall-cmd --zone="$DEFAULT_ZONE" --add-rich-rule='rule drop log prefix="DROP INVALID " level="warning" limit value="5/m"' --permanent
log_info "✓ Invalid packet dropping configured"
((RULES_CONFIGURED++))

# Block ping floods
firewall-cmd --zone="$DEFAULT_ZONE" --add-rich-rule='rule protocol value="icmp" limit value="1/s" accept' --permanent
log_info "✓ ICMP rate limiting configured"
((RULES_CONFIGURED++))

# Enable panic mode protection (optional - uncomment if needed)
# firewall-cmd --panic-on

# Configure logging for denied packets
firewall-cmd --set-log-denied=all --permanent
log_info "✓ Logging for denied packets enabled"
((RULES_CONFIGURED++))

# Reload firewall to apply changes
log_info "Reloading firewall configuration..."

firewall-cmd --reload

log_info "✓ Firewall configuration reloaded"

# Verify configuration
log_info "Verifying firewall configuration..."

ACTIVE_ZONE=$(firewall-cmd --get-active-zones | head -n1)
log_info "  Active zone: $ACTIVE_ZONE"

SERVICES=$(firewall-cmd --zone="$DEFAULT_ZONE" --list-services)
log_info "  Allowed services: ${SERVICES:-none}"

PORTS=$(firewall-cmd --zone="$DEFAULT_ZONE" --list-ports)
log_info "  Allowed ports: ${PORTS:-none}"

# Display rich rules
log_info "Rich rules configured:"
firewall-cmd --zone="$DEFAULT_ZONE" --list-rich-rules | while IFS= read -r rule; do
    log_info "    $rule"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Firewall Hardening Summary"
log_info "=============================================="
log_info "Default zone: $(firewall-cmd --get-default-zone)"
log_info "SSH port: $SSH_PORT"
log_info "Rules configured: $RULES_CONFIGURED"
log_info "Service status: $(systemctl is-active firewalld)"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Firewall hardening completed!"
log_info ""
log_info "To manage firewall:"
log_info "  - List zones: firewall-cmd --get-zones"
log_info "  - List services: firewall-cmd --list-services"
log_info "  - Add service: firewall-cmd --add-service=SERVICE --permanent && firewall-cmd --reload"
log_info "  - Add port: firewall-cmd --add-port=PORT/tcp --permanent && firewall-cmd --reload"