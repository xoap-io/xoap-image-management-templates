#!/bin/bash
#===================================================================================
# Script: configure_grub_ubuntu.sh
# Description: Configure GRUB bootloader for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./configure_grub_ubuntu.sh [--timeout SECONDS]
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
GRUB_TIMEOUT="${GRUB_TIMEOUT:-5}"
KERNEL_PARAMS="${KERNEL_PARAMS:-}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            GRUB_TIMEOUT="$2"
            shift 2
            ;;
        --kernel-params)
            KERNEL_PARAMS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting GRUB configuration for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_MODIFIED=0

# Detect GRUB configuration file
if [[ -f /etc/default/grub ]]; then
    GRUB_DEFAULT="/etc/default/grub"
else
    log_error "GRUB configuration file not found"
    exit 1
fi

# Backup GRUB configuration
BACKUP_FILE="${GRUB_DEFAULT}.backup.$(date +%Y%m%d-%H%M%S)"
cp "$GRUB_DEFAULT" "$BACKUP_FILE"
log_info "Backed up GRUB configuration to $BACKUP_FILE"

# Modify GRUB timeout
log_info "Setting GRUB timeout to ${GRUB_TIMEOUT} seconds..."

if grep -q "^GRUB_TIMEOUT=" "$GRUB_DEFAULT"; then
    sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT}/" "$GRUB_DEFAULT"
else
    echo "GRUB_TIMEOUT=${GRUB_TIMEOUT}" >> "$GRUB_DEFAULT"
fi

log_info "✓ GRUB timeout configured"
((CONFIGS_MODIFIED++))

# Disable recovery mode
log_info "Disabling recovery mode menu entries..."

if grep -q "^GRUB_DISABLE_RECOVERY=" "$GRUB_DEFAULT"; then
    sed -i 's/^GRUB_DISABLE_RECOVERY=.*/GRUB_DISABLE_RECOVERY="true"/' "$GRUB_DEFAULT"
else
    echo 'GRUB_DISABLE_RECOVERY="true"' >> "$GRUB_DEFAULT"
fi

log_info "✓ Recovery mode disabled"
((CONFIGS_MODIFIED++))

# Configure kernel command line parameters
if [[ -n "$KERNEL_PARAMS" ]]; then
    log_info "Adding kernel parameters: $KERNEL_PARAMS"
    
    if grep -q "^GRUB_CMDLINE_LINUX=" "$GRUB_DEFAULT"; then
        CURRENT_PARAMS=$(grep "^GRUB_CMDLINE_LINUX=" "$GRUB_DEFAULT" | sed 's/GRUB_CMDLINE_LINUX="//' | sed 's/"$//')
        
        for param in $KERNEL_PARAMS; do
            if [[ ! "$CURRENT_PARAMS" =~ $param ]]; then
                CURRENT_PARAMS="$CURRENT_PARAMS $param"
            fi
        done
        
        sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${CURRENT_PARAMS}\"|" "$GRUB_DEFAULT"
    else
        echo "GRUB_CMDLINE_LINUX=\"${KERNEL_PARAMS}\"" >> "$GRUB_DEFAULT"
    fi
    
    log_info "✓ Kernel parameters configured"
    ((CONFIGS_MODIFIED++))
fi

# Add security-related kernel parameters
log_info "Adding security kernel parameters..."

SECURITY_PARAMS="audit=1"

if grep -q "^GRUB_CMDLINE_LINUX=" "$GRUB_DEFAULT"; then
    CURRENT_PARAMS=$(grep "^GRUB_CMDLINE_LINUX=" "$GRUB_DEFAULT" | sed 's/GRUB_CMDLINE_LINUX="//' | sed 's/"$//')
    
    for param in $SECURITY_PARAMS; do
        param_name=$(echo "$param" | cut -d'=' -f1)
        if [[ ! "$CURRENT_PARAMS" =~ $param_name ]]; then
            CURRENT_PARAMS="$CURRENT_PARAMS $param"
        fi
    done
    
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${CURRENT_PARAMS}\"|" "$GRUB_DEFAULT"
else
    echo "GRUB_CMDLINE_LINUX=\"${SECURITY_PARAMS}\"" >> "$GRUB_DEFAULT"
fi

log_info "✓ Security parameters added"
((CONFIGS_MODIFIED++))

# Display current GRUB configuration
log_info "Current GRUB configuration:"
grep -E "^GRUB_" "$GRUB_DEFAULT" | while IFS= read -r line; do
    log_info "  $line"
done

# Update GRUB configuration
log_info "Updating GRUB configuration..."

if update-grub 2>&1 | tee /tmp/grub-update.log; then
    log_info "✓ GRUB configuration updated"
    ((CONFIGS_MODIFIED++))
else
    log_error "Failed to update GRUB configuration"
    cat /tmp/grub-update.log
    exit 1
fi

# Verify GRUB configuration file
GRUB_CFG="/boot/grub/grub.cfg"

if [[ -f "$GRUB_CFG" ]]; then
    MENU_ENTRIES=$(grep -c "^menuentry" "$GRUB_CFG" || echo "0")
    log_info "✓ GRUB configuration verified ($MENU_ENTRIES menu entries)"
else
    log_error "GRUB configuration file not found: $GRUB_CFG"
    exit 1
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "GRUB Configuration Summary"
log_info "=============================================="
log_info "Configuration file: $GRUB_DEFAULT"
log_info "GRUB config: $GRUB_CFG"
log_info "Timeout: ${GRUB_TIMEOUT} seconds"
log_info "Menu entries: $MENU_ENTRIES"
log_info "Configurations modified: $CONFIGS_MODIFIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "GRUB configuration completed!"
log_info ""
log_info "Changes will take effect on next boot"