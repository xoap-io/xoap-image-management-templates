#!/usr/bin/env bash
#
# sudoers_ubuntu.sh
#
# SYNOPSIS
#   Configures sudoers for vagrant user
#
# DESCRIPTION
#   Sets up password-less sudo for vagrant user and configures
#   sudo group exemption for environment reset
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Sudoers]"
readonly SUDOERS_FILE="/etc/sudoers"
readonly VAGRANT_SUDOERS="/etc/sudoers.d/99_vagrant"

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

log_info "=== Starting Sudoers Configuration ==="

# Backup main sudoers file
sudoers_backup="${SUDOERS_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
log_info "Backing up sudoers file..."
cp "$SUDOERS_FILE" "$sudoers_backup"
log_info "Backup saved to: $sudoers_backup"

# Add exempt_group=sudo to main sudoers file
log_info "Configuring sudo group exemption..."
if grep -q "exempt_group=sudo" "$SUDOERS_FILE"; then
    log_info "Sudo group exemption already configured"
else
    # Add after Defaults env_reset line
    sed -i '/^Defaults\s\+env_reset/a Defaults\texempt_group=sudo' "$SUDOERS_FILE"
    log_info "Sudo group exemption added"
fi

# Validate main sudoers file
if visudo -c -f "$SUDOERS_FILE"; then
    log_info "Main sudoers file is valid"
else
    log_warn "Main sudoers file validation failed, restoring backup..."
    cp "$sudoers_backup" "$SUDOERS_FILE"
    error_exit "Sudoers file invalid, backup restored" 1
fi

# Create vagrant sudoers file
log_info "Creating password-less sudo configuration for vagrant user..."
cat <<'EOF' > "$VAGRANT_SUDOERS"
# XOAP Image Management - Vagrant User Sudo Configuration
# Generated on: $(date)

# Allow vagrant user to run any command without password
vagrant ALL=(ALL) NOPASSWD:ALL

# Preserve environment variables for vagrant
Defaults:vagrant !requiretty
Defaults:vagrant env_keep += "SSH_AUTH_SOCK"
EOF

# Set proper permissions
chmod 0440 "$VAGRANT_SUDOERS"
log_info "Vagrant sudoers file created with proper permissions"

# Validate vagrant sudoers file
if visudo -c -f "$VAGRANT_SUDOERS"; then
    log_info "Vagrant sudoers file is valid"
else
    log_warn "Vagrant sudoers file validation failed, removing..."
    rm -f "$VAGRANT_SUDOERS"
    error_exit "Vagrant sudoers file invalid" 1
fi

# Verify vagrant user exists
if id vagrant &>/dev/null; then
    log_info "Vagrant user exists"
    
    # Add vagrant to sudo group
    if usermod -aG sudo vagrant; then
        log_info "Vagrant user added to sudo group"
    else
        log_warn "Failed to add vagrant user to sudo group"
    fi
else
    log_warn "Vagrant user does not exist"
    log_info "Note: The sudoers configuration will be ready when vagrant user is created"
fi

log_info "=== Sudoers Configuration Completed ==="
log_info "Configuration files:"
log_info "  Main: $SUDOERS_FILE"
log_info "  Vagrant: $VAGRANT_SUDOERS"
log_info "  Backup: $sudoers_backup"
