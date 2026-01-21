#!/usr/bin/env bash
#
# systemd_ubuntu.sh
#
# SYNOPSIS
#   Ensures proper systemd PAM integration
#
# DESCRIPTION
#   Installs libpam-systemd for proper systemd session management
#   This is required for user sessions to work correctly with systemd
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges

set -Eeuo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Systemd]"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [INFO] $*"
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

log_info "=== Starting Systemd PAM Integration Setup ==="
log_info "Purpose: Ensure libpam-systemd is installed for proper session management"
log_info "Reference: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=751636"

# Check if already installed
if dpkg -l | grep -q "^ii  libpam-systemd"; then
    log_info "libpam-systemd is already installed"
    version=$(dpkg -l | grep "^ii  libpam-systemd" | awk '{print $3}')
    log_info "Installed version: $version"
else
    log_info "libpam-systemd not found, installing..."
    
    # Update package lists
    log_info "Updating package lists..."
    apt-get update -qq
    
    # Install libpam-systemd
    log_info "Installing libpam-systemd..."
    if apt-get install -y libpam-systemd; then
        log_info "libpam-systemd installed successfully"
        version=$(dpkg -l | grep "^ii  libpam-systemd" | awk '{print $3}')
        log_info "Installed version: $version"
    else
        error_exit "Failed to install libpam-systemd" 1
    fi
fi

# Verify PAM configuration
log_info "Verifying PAM configuration..."
if grep -q "pam_systemd" /etc/pam.d/common-session; then
    log_info "PAM systemd integration is configured"
else
    log_info "PAM systemd integration not found in common-session"
fi

log_info "=== Systemd PAM Integration Setup Completed ==="
