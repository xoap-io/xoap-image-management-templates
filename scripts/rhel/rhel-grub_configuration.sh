#!/bin/bash
#===================================================================================
# Script: grub_configuration.sh
# Description: Configure GRUB bootloader for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./grub_configuration.sh
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

log_info "Starting GRUB configuration..."

# Configuration variables
GRUB_CONFIG="/etc/default/grub"
BACKUP_DIR="/root/grub_backups"
START_TIME=$(date +%s)

# Configuration parameters
GRUB_TIMEOUT="${1:-1}"
GRUB_CMDLINE_PARAMS="${2:-}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup existing GRUB configuration
if [[ -f "$GRUB_CONFIG" ]]; then
    BACKUP_FILE="$BACKUP_DIR/grub.$(date +%Y%m%d_%H%M%S).bak"
    log_info "Backing up GRUB configuration to: $BACKUP_FILE"
    cp "$GRUB_CONFIG" "$BACKUP_FILE"
fi

# Display current GRUB timeout
CURRENT_TIMEOUT=$(grep -oP '^GRUB_TIMEOUT=\K\d+' "$GRUB_CONFIG" 2>/dev/null || echo "unknown")
log_info "Current GRUB timeout: ${CURRENT_TIMEOUT}s"

# Update GRUB timeout
log_info "Setting GRUB timeout to ${GRUB_TIMEOUT}s"
if grep -q "^GRUB_TIMEOUT=" "$GRUB_CONFIG"; then
    sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$GRUB_TIMEOUT/" "$GRUB_CONFIG"
else
    echo "GRUB_TIMEOUT=$GRUB_TIMEOUT" >> "$GRUB_CONFIG"
fi

# Disable GRUB recovery mode (optional)
log_info "Disabling GRUB recovery mode..."
if grep -q "^GRUB_DISABLE_RECOVERY=" "$GRUB_CONFIG"; then
    sed -i 's/^GRUB_DISABLE_RECOVERY=.*/GRUB_DISABLE_RECOVERY=true/' "$GRUB_CONFIG"
else
    echo "GRUB_DISABLE_RECOVERY=true" >> "$GRUB_CONFIG"
fi

# Add custom kernel parameters if provided
if [[ -n "$GRUB_CMDLINE_PARAMS" ]]; then
    log_info "Adding custom kernel parameters: $GRUB_CMDLINE_PARAMS"
    
    if grep -q "^GRUB_CMDLINE_LINUX=" "$GRUB_CONFIG"; then
        # Add to existing GRUB_CMDLINE_LINUX
        sed -i "/^GRUB_CMDLINE_LINUX=/s/\"\$/ $GRUB_CMDLINE_PARAMS\"/" "$GRUB_CONFIG"
    else
        echo "GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_PARAMS\"" >> "$GRUB_CONFIG"
    fi
fi

# Regenerate GRUB configuration
log_info "Regenerating GRUB configuration..."

# Detect GRUB configuration file location
if [[ -f /boot/grub2/grub.cfg ]]; then
    GRUB_CFG="/boot/grub2/grub.cfg"
    log_info "Detected BIOS boot mode"
elif [[ -f /boot/efi/EFI/redhat/grub.cfg ]]; then
    GRUB_CFG="/boot/efi/EFI/redhat/grub.cfg"
    log_info "Detected UEFI boot mode (RedHat)"
elif [[ -f /boot/efi/EFI/centos/grub.cfg ]]; then
    GRUB_CFG="/boot/efi/EFI/centos/grub.cfg"
    log_info "Detected UEFI boot mode (CentOS)"
elif [[ -f /boot/efi/EFI/rocky/grub.cfg ]]; then
    GRUB_CFG="/boot/efi/EFI/rocky/grub.cfg"
    log_info "Detected UEFI boot mode (Rocky)"
elif [[ -f /boot/efi/EFI/almalinux/grub.cfg ]]; then
    GRUB_CFG="/boot/efi/EFI/almalinux/grub.cfg"
    log_info "Detected UEFI boot mode (AlmaLinux)"
else
    # Try to find any GRUB config in EFI
    GRUB_CFG=$(find /boot/efi/EFI -name grub.cfg 2>/dev/null | head -1 || echo "")
    if [[ -z "$GRUB_CFG" ]]; then
        log_error "Could not locate GRUB configuration file"
        exit 1
    fi
    log_info "Found GRUB configuration: $GRUB_CFG"
fi

# Backup GRUB config file
GRUB_CFG_BACKUP="$BACKUP_DIR/grub.cfg.$(date +%Y%m%d_%H%M%S).bak"
log_info "Backing up GRUB config file to: $GRUB_CFG_BACKUP"
cp "$GRUB_CFG" "$GRUB_CFG_BACKUP"

# Regenerate GRUB configuration
if grub2-mkconfig -o "$GRUB_CFG" 2>&1 | tee /tmp/grub-mkconfig.log; then
    log_info "GRUB configuration regenerated successfully"
else
    log_error "Failed to regenerate GRUB configuration"
    log_error "Restoring backup..."
    cp "$BACKUP_FILE" "$GRUB_CONFIG"
    cp "$GRUB_CFG_BACKUP" "$GRUB_CFG"
    exit 1
fi

# Verify GRUB configuration
log_info "Verifying GRUB configuration..."
NEW_TIMEOUT=$(grep -oP '^GRUB_TIMEOUT=\K\d+' "$GRUB_CONFIG")

if [[ "$NEW_TIMEOUT" == "$GRUB_TIMEOUT" ]]; then
    log_info "✓ GRUB timeout verified: ${NEW_TIMEOUT}s"
else
    log_warn "✗ GRUB timeout mismatch: expected $GRUB_TIMEOUT, got $NEW_TIMEOUT"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "GRUB Configuration Summary"
log_info "=============================================="
log_info "Configuration file: $GRUB_CONFIG"
log_info "GRUB config file: $GRUB_CFG"
log_info "Boot timeout: ${GRUB_TIMEOUT}s"
log_info "Recovery mode: disabled"
if [[ -n "$GRUB_CMDLINE_PARAMS" ]]; then
    log_info "Custom parameters: $GRUB_CMDLINE_PARAMS"
fi
log_info "Backup saved to: $BACKUP_FILE"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "GRUB configuration completed successfully!"