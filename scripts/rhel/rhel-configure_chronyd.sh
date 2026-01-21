#!/bin/bash
#===================================================================================
# Script: configure_chronyd.sh
# Description: Configure chrony time synchronization for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./configure_chronyd.sh
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

log_info "Starting chrony configuration..."

# Configuration variables
CHRONY_CONF="/etc/chrony.conf"
BACKUP_DIR="/root/chrony_backups"
START_TIME=$(date +%s)
TIMEZONE="${1:-UTC}"

# NTP servers (customize as needed)
NTP_SERVERS=(
    "0.pool.ntp.org"
    "1.pool.ntp.org"
    "2.pool.ntp.org"
    "3.pool.ntp.org"
)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if chrony is installed
if ! command -v chronyd &>/dev/null; then
    log_warn "chrony is not installed. Installing..."
    if command -v dnf &>/dev/null; then
        dnf install -y chrony
    elif command -v yum &>/dev/null; then
        yum install -y chrony
    else
        log_error "Cannot install chrony - no package manager found"
        exit 1
    fi
fi

# Backup existing configuration
if [[ -f "$CHRONY_CONF" ]]; then
    BACKUP_FILE="$BACKUP_DIR/chrony.conf.$(date +%Y%m%d_%H%M%S).bak"
    log_info "Backing up chrony configuration to: $BACKUP_FILE"
    cp "$CHRONY_CONF" "$BACKUP_FILE"
fi

# Configure chrony
log_info "Configuring chrony NTP servers..."

# Remove existing server/pool lines
sed -i '/^server\|^pool/d' "$CHRONY_CONF"

# Add NTP servers
for server in "${NTP_SERVERS[@]}"; do
    log_info "Adding NTP server: $server"
    echo "pool $server iburst" >> "$CHRONY_CONF"
done

# Set timezone
log_info "Setting timezone to: $TIMEZONE"
if timedatectl set-timezone "$TIMEZONE" 2>/dev/null; then
    log_info "Timezone set successfully"
else
    log_warn "Failed to set timezone (may not be critical)"
fi

# Enable and start chronyd
log_info "Enabling and starting chronyd service..."
systemctl enable chronyd
systemctl restart chronyd

# Wait for chrony to synchronize
sleep 5

# Verify chrony status
log_info "Verifying chrony status..."
CHRONY_STATUS=$(systemctl is-active chronyd)

if [[ "$CHRONY_STATUS" == "active" ]]; then
    log_info "chronyd service is active"
else
    log_error "chronyd service is not active"
    exit 1
fi

# Display chrony tracking
log_info "Chrony tracking information:"
chronyc tracking | while IFS= read -r line; do
    log_info "  $line"
done

# Display NTP sources
log_info "NTP sources:"
chronyc sources | while IFS= read -r line; do
    log_info "  $line"
done

# Display current time
log_info "Current system time: $(date)"
log_info "Current timezone: $(timedatectl | grep 'Time zone' | awk '{print $3}')"

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Chrony Configuration Summary"
log_info "=============================================="
log_info "Configuration file: $CHRONY_CONF"
log_info "NTP servers configured: ${#NTP_SERVERS[@]}"
log_info "Timezone: $TIMEZONE"
log_info "Service status: $CHRONY_STATUS"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Chrony configuration completed successfully!"