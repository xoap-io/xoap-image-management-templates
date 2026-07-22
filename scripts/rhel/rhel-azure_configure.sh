#!/bin/bash
#===================================================================================
# Script: azure_configure.sh
# Description: Configure Azure-specific settings for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./azure_configure.sh
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

log_info "Starting Azure configuration..."

# Statistics tracking
START_TIME=$(date +%s)
TASKS_COMPLETED=0
TASKS_FAILED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

#===================================================================================
# Task 1: Install WALinuxAgent
#===================================================================================
log_info "[Task 1/3] Installing Azure Linux Agent (WALinuxAgent)..."

if rpm -q WALinuxAgent &>/dev/null; then
    log_info "WALinuxAgent is already installed"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    if $PKG_MGR install -y WALinuxAgent 2>&1 | tee -a /tmp/azure-config.log; then
        log_info "WALinuxAgent installed successfully"
        TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    else
        log_warn "Failed to install WALinuxAgent"
        TASKS_FAILED=$((TASKS_FAILED + 1))
    fi
fi

# Configure WALinuxAgent
if [[ -f /etc/waagent.conf ]]; then
    log_info "Configuring WALinuxAgent..."
    
    # Enable provisioning
    sed -i 's/Provisioning.Enabled=n/Provisioning.Enabled=y/g' /etc/waagent.conf
    
    # Enable resource disk formatting
    sed -i 's/ResourceDisk.Format=n/ResourceDisk.Format=y/g' /etc/waagent.conf
    
    # Enable swap on resource disk
    sed -i 's/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g' /etc/waagent.conf
    sed -i 's/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=2048/g' /etc/waagent.conf
    
    log_info "WALinuxAgent configured"
    
    # Enable and start service
    systemctl enable waagent
    systemctl start waagent
    
    log_info "WALinuxAgent service enabled and started"
fi

#===================================================================================
# Task 2: Install cloud-init
#===================================================================================
log_info "[Task 2/3] Installing cloud-init..."

if rpm -q cloud-init &>/dev/null; then
    log_info "cloud-init is already installed"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    if $PKG_MGR install -y cloud-init 2>&1 | tee -a /tmp/azure-config.log; then
        log_info "cloud-init installed successfully"
        TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    else
        log_warn "Failed to install cloud-init"
        TASKS_FAILED=$((TASKS_FAILED + 1))
    fi
fi

# Configure cloud-init for Azure
if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    log_info "Configuring cloud-init datasource for Azure..."
    
    cat <<'EOF' > /etc/cloud/cloud.cfg.d/91_azure_datasource.cfg
# Azure-specific cloud-init configuration
datasource_list: [ Azure ]
datasource:
  Azure:
    apply_network_config: true
EOF
    
    log_info "cloud-init configured for Azure"
fi

#===================================================================================
# Task 3: Configure kernel parameters for Azure
#===================================================================================
log_info "[Task 3/3] Configuring kernel parameters for Azure..."

GRUB_CONFIG="/etc/default/grub"

if [[ -f "$GRUB_CONFIG" ]]; then
    # Add Azure-specific kernel parameters
    AZURE_PARAMS="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300"
    
    if grep -q "GRUB_CMDLINE_LINUX=" "$GRUB_CONFIG"; then
        # Check if Azure params already exist
        if ! grep -q "console=ttyS0" "$GRUB_CONFIG"; then
            sed -i "/GRUB_CMDLINE_LINUX=/s/\"\$/ $AZURE_PARAMS\"/" "$GRUB_CONFIG"
            log_info "Added Azure kernel parameters"
            
            # Regenerate GRUB configuration
            if [[ -f /boot/grub2/grub.cfg ]]; then
                grub2-mkconfig -o /boot/grub2/grub.cfg
            elif [[ -f /boot/efi/EFI/redhat/grub.cfg ]]; then
                grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
            fi
            
            log_info "GRUB configuration regenerated"
        else
            log_info "Azure kernel parameters already configured"
        fi
    fi
    
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    log_warn "GRUB configuration not found"
    TASKS_FAILED=$((TASKS_FAILED + 1))
fi

# Configure network for Azure
log_info "Configuring network settings for Azure..."

# Disable NetworkManager cloud-setup if present
if systemctl list-unit-files | grep -q "nm-cloud-setup"; then
    systemctl disable nm-cloud-setup.service 2>/dev/null || true
    systemctl disable nm-cloud-setup.timer 2>/dev/null || true
fi

# Enable dhcp on eth0
if [[ -d /etc/sysconfig/network-scripts ]]; then
    cat <<'EOF' > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
EOF
    
    log_info "Network configuration created for eth0"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Azure Configuration Summary"
log_info "=============================================="
log_info "Tasks completed: $TASKS_COMPLETED/3"
log_info "Tasks failed: $TASKS_FAILED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Azure configuration completed!"
log_info ""
log_info "NOTE: System will need to be deprovisioned before creating image:"
log_info "  waagent -force -deprovision+user"