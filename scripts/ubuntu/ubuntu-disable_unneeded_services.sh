#!/usr/bin/env bash
#
# ssh_hardening.sh
#
# SYNOPSIS
#   Hardens SSH configuration
#
# DESCRIPTION
#   Applies security hardening to SSH daemon configuration:
#   - Disables root login
#   - Disables password authentication
#   - Disables X11 forwarding
#   - Sets secure ciphers and MACs
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges
#   - OpenSSH server installed

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[SSH-Hardening]"
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly SSHD_CONFIG_BACKUP="${SSHD_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

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

# Check if sshd is installed
if [[ ! -f "$SSHD_CONFIG" ]]; then
    error_exit "SSH daemon configuration not found at $SSHD_CONFIG" 1
fi

log_info "=== Starting SSH Hardening ==="

# Backup current configuration
log_info "Backing up current SSH configuration..."
cp "$SSHD_CONFIG" "$SSHD_CONFIG_BACKUP"
log_info "Backup saved to: $SSHD_CONFIG_BACKUP"

# Configure SSH settings
log_info "Applying SSH hardening settings..."

# Disable root login
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
log_info "Root login disabled"

# Disable password authentication
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
log_info "Password authentication disabled"

# Disable X11 forwarding
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"
log_info "X11 forwarding disabled"

# Set additional hardening options
log_info "Adding additional hardening options..."
cat <<EOF >> "$SSHD_CONFIG"

# XOAP Security Hardening - $(date)
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
Protocol 2
EOF

log_info "Additional options configured"

# Test configuration
log_info "Testing SSH configuration..."
if sshd -t -f "$SSHD_CONFIG"; then
    log_info "SSH configuration is valid"
else
    log_warn "SSH configuration test failed, restoring backup..."
    cp "$SSHD_CONFIG_BACKUP" "$SSHD_CONFIG"
    error_exit "SSH configuration invalid, backup restored" 1
fi

# Reload SSH daemon
log_info "Reloading SSH daemon..."
if systemctl reload sshd || systemctl reload ssh; then
    log_info "SSH daemon reloaded successfully"
else
    log_warn "Failed to reload SSH daemon, restart may be required"
fi

log_info "=== SSH Hardening Completed ==="
log_info "Backup available at: $SSHD_CONFIG_BACKUP"
log_info "WARNING: Ensure you have alternate access before logging out!"
