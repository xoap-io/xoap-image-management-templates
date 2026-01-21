#!/usr/bin/env bash
#
# networking_ubuntu.sh
#
# SYNOPSIS
#   Configures network settings for Ubuntu
#
# DESCRIPTION
#   Sets up network configuration:
#   - Creates netplan configuration for eth0 (Ubuntu 18+)
#   - Disables predictable network interface names
#   - Uses traditional eth0 naming
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Networking]"

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

log_info "=== Starting Network Configuration ==="

# Get Ubuntu version
ubuntu_version=$(lsb_release -r | awk '{print $2}')
major_version=$(echo "$ubuntu_version" | awk -F. '{print $1}')

log_info "Ubuntu version: $ubuntu_version (major: $major_version)"

# Configure based on version
if [[ $major_version -ge 18 ]]; then
    log_info "Configuring netplan for Ubuntu 18+..."
    
    # Create netplan configuration directory
    mkdir -p /etc/netplan
    
    # Backup existing netplan configs
    if ls /etc/netplan/*.yaml &>/dev/null; then
        log_info "Backing up existing netplan configurations..."
        for file in /etc/netplan/*.yaml; do
            cp "$file" "${file}.backup.$(date +%Y%m%d-%H%M%S)"
        done
    fi
    
    # Create new netplan configuration
    log_info "Creating netplan configuration for eth0..."
    cat <<'EOF' > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
      optional: true
EOF
    
    # Set proper permissions
    chmod 600 /etc/netplan/01-netcfg.yaml
    
    log_info "Netplan configuration created"
    
    # Test netplan configuration
    if netplan generate; then
        log_info "Netplan configuration is valid"
    else
        log_warn "Netplan configuration may have issues"
    fi
else
    log_info "Configuring legacy networking for Ubuntu <18..."
    
    # Add delay for interface up
    if [[ -f /etc/network/interfaces ]]; then
        if ! grep -q "pre-up sleep 2" /etc/network/interfaces; then
            echo "pre-up sleep 2" >> /etc/network/interfaces
            log_info "Added 2-second delay to interface startup"
        fi
        
        # Replace new-style names with eth0
        sed -i 's/en[[:alnum:]]*/eth0/g' /etc/network/interfaces
        log_info "Replaced interface names with eth0"
    fi
fi

# Disable Predictable Network Interface Names
log_info "Disabling predictable network interface names..."

grub_config="/etc/default/grub"
if [[ -f "$grub_config" ]]; then
    # Backup GRUB config
    cp "$grub_config" "${grub_config}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Add kernel parameters to disable predictable names
    if grep -q 'GRUB_CMDLINE_LINUX=' "$grub_config"; then
        sed -i 's/GRUB_CMDLINE_LINUX="\([^"]*\)"/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0 \1"/g' "$grub_config"
        log_info "Added kernel parameters to GRUB configuration"
        
        # Update GRUB
        if update-grub; then
            log_info "GRUB configuration updated successfully"
        else
            log_warn "Failed to update GRUB configuration"
        fi
    else
        log_warn "GRUB_CMDLINE_LINUX not found in $grub_config"
    fi
else
    log_warn "GRUB configuration file not found at $grub_config"
fi

log_info "=== Network Configuration Completed ==="
log_info "A reboot is required for changes to take effect"
log_info "Interface will be named 'eth0' after reboot"
