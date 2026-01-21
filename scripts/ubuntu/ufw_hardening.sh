#!/usr/bin/env bash
#
# ufw_hardening.sh
#
# SYNOPSIS
#   Configures and enables UFW firewall
#
# DESCRIPTION
#   Sets up UFW (Uncomplicated Firewall) with secure defaults:
#   - Denies all incoming traffic by default
#   - Allows all outgoing traffic
#   - Allows SSH (OpenSSH)
#   - Enables logging
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges
#   - UFW installed

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[UFW-Hardening]"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [INFO] $*"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [WARN] $*" >&2
}

error_exit() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [ERROR] $*" >&2
    exit "${2:-1}"
}

trap 'error_exit "Script failed at line $LINENO" "$?"' ERR

# Check root privileges
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root or with sudo" 1
fi

# Check if UFW is installed
if ! command -v ufw &>/dev/null; then
    log_warn "UFW not installed, installing..."
    apt-get update -qq
    apt-get install -y ufw
    log_info "UFW installed successfully"
fi

log_info "=== Starting UFW Firewall Configuration ==="

# Reset UFW to defaults (for clean configuration)
log_info "Resetting UFW to default configuration..."
ufw --force reset >/dev/null

# Set default policies
log_info "Setting default firewall policies..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# Allow SSH (critical - do this before enabling!)
log_info "Allowing SSH connections..."
if ufw allow OpenSSH; then
    log_info "SSH access allowed (OpenSSH profile)"
else
    log_warn "OpenSSH profile not found, allowing port 22 directly"
    ufw allow 22/tcp comment 'SSH'
fi

# Enable logging
log_info "Enabling firewall logging..."
ufw logging on

# Additional rate limiting for SSH
log_info "Enabling rate limiting for SSH..."
ufw limit ssh/tcp comment 'SSH rate limit'

# Enable UFW
log_info "Enabling UFW firewall..."
log_warn "IMPORTANT: Ensure SSH access is working before enabling firewall!"
sleep 2

if ufw --force enable; then
    log_info "UFW firewall enabled successfully"
else
    error_exit "Failed to enable UFW firewall" 1
fi

# Display status
log_info "=== UFW Firewall Status ==="
ufw status verbose

log_info "=== UFW Hardening Completed ==="
log_info "Firewall is now active and protecting the system"
log_info "To add more rules, use: ufw allow <port>/<protocol>"
