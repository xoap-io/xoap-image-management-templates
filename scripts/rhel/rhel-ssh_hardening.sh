#!/bin/bash
#===================================================================================
# Script: ssh_hardening.sh
# Description: Apply SSH hardening configuration for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./ssh_hardening.sh
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

log_info "Starting SSH hardening configuration..."

# Configuration variables
SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ssh_backups"
START_TIME=$(date +%s)
SETTINGS_APPLIED=0

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup existing SSH configuration
BACKUP_FILE="$BACKUP_DIR/sshd_config.$(date +%Y%m%d_%H%M%S).bak"
log_info "Backing up SSH configuration to: $BACKUP_FILE"
cp "$SSH_CONFIG" "$BACKUP_FILE"

# Function to set or update SSH configuration
set_ssh_config() {
    local setting="$1"
    local value="$2"
    local description="$3"
    
    log_info "Configuring: $description"
    
    # Check if setting exists (commented or uncommented)
    if grep -qE "^#?${setting}" "$SSH_CONFIG"; then
        # Update existing setting
        sed -i "s/^#\?${setting}.*/${setting} ${value}/" "$SSH_CONFIG"
    else
        # Append new setting
        echo "${setting} ${value}" >> "$SSH_CONFIG"
    fi
    
    SETTINGS_APPLIED=$((SETTINGS_APPLIED + 1))
}

# Apply SSH hardening settings
log_info "Applying SSH security hardening..."

# Disable root login
set_ssh_config "PermitRootLogin" "no" "Disable root login"

# Disable password authentication (use key-based auth only)
set_ssh_config "PasswordAuthentication" "no" "Disable password authentication"

# Disable X11 forwarding
set_ssh_config "X11Forwarding" "no" "Disable X11 forwarding"

# Disable empty passwords
set_ssh_config "PermitEmptyPasswords" "no" "Disable empty passwords"

# Disable challenge-response authentication
set_ssh_config "ChallengeResponseAuthentication" "no" "Disable challenge-response auth"

# Enable PAM
set_ssh_config "UsePAM" "yes" "Enable PAM"

# Disable TCP forwarding
set_ssh_config "AllowTcpForwarding" "no" "Disable TCP forwarding"

# Set maximum authentication attempts
set_ssh_config "MaxAuthTries" "3" "Set max auth attempts to 3"

# Set login grace time
set_ssh_config "LoginGraceTime" "30" "Set login grace time to 30 seconds"

# Set client alive interval (timeout)
set_ssh_config "ClientAliveInterval" "300" "Set client alive interval to 5 minutes"

# Set client alive count max
set_ssh_config "ClientAliveCountMax" "2" "Set client alive count max to 2"

# Disable agent forwarding
set_ssh_config "AllowAgentForwarding" "no" "Disable agent forwarding"

# Limit concurrent connections
set_ssh_config "MaxStartups" "10:30:60" "Limit concurrent unauthenticated connections"

# Use strong encryption algorithms (modern ciphers only)
log_info "Configuring strong encryption algorithms..."
cat <<'EOF' >> "$SSH_CONFIG"

# Strong Encryption Configuration
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
EOF

SETTINGS_APPLIED=$((SETTINGS_APPLIED + 3))

# Validate SSH configuration
log_info "Validating SSH configuration..."
if sshd -t 2>/dev/null; then
    log_info "SSH configuration validation successful"
else
    log_error "SSH configuration validation failed!"
    log_error "Restoring backup configuration..."
    cp "$BACKUP_FILE" "$SSH_CONFIG"
    exit 1
fi

# Reload SSH daemon
log_info "Reloading SSH daemon..."
if systemctl reload sshd 2>/dev/null; then
    log_info "SSH daemon reloaded successfully"
else
    log_error "Failed to reload SSH daemon"
    exit 1
fi

# Verify SSH daemon status
SSH_STATUS=$(systemctl is-active sshd 2>/dev/null)
if [[ "$SSH_STATUS" == "active" ]]; then
    log_info "SSH daemon is active and running"
else
    log_error "SSH daemon is not running properly"
    exit 1
fi

# Display critical settings
log_info "Verifying critical SSH security settings..."
grep -E "^(PermitRootLogin|PasswordAuthentication|X11Forwarding|PermitEmptyPasswords)" "$SSH_CONFIG" | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "SSH Hardening Summary"
log_info "=============================================="
log_info "Configuration file: $SSH_CONFIG"
log_info "Backup saved to: $BACKUP_FILE"
log_info "Settings applied: $SETTINGS_APPLIED"
log_info "SSH daemon status: $SSH_STATUS"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "SSH hardening completed successfully!"
log_info ""
log_warn "IMPORTANT: Ensure you have SSH key-based authentication configured"
log_warn "before logging out, as password authentication is now disabled!"