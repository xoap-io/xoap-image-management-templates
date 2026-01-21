#!/bin/bash
#===================================================================================
# Script: azure_configure_suse.sh
# Description: Configure SUSE/openSUSE for Microsoft Azure
# Author: XOAP Infrastructure Team
# Usage: ./azure_configure_suse.sh
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

log_info "Starting Azure configuration for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Detect if running on Azure
log_info "Detecting cloud platform..."

if [[ -f /sys/class/dmi/id/sys_vendor ]] && grep -qi "Microsoft Corporation" /sys/class/dmi/id/sys_vendor; then
    log_info "Running on Microsoft Azure"
elif curl -s -H Metadata:true -m 2 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" &>/dev/null; then
    log_info "Azure metadata service detected"
else
    log_warn "Not running on Azure - some features may not work"
fi

# Install WALinuxAgent
log_info "Installing WALinuxAgent..."

if ! rpm -q python-azure-agent &>/dev/null && ! rpm -q WALinuxAgent &>/dev/null; then
    if zypper install -y WALinuxAgent; then
        log_info "✓ WALinuxAgent installed"
        ((CONFIGS_APPLIED++))
    else
        log_error "Failed to install WALinuxAgent"
        exit 1
    fi
else
    log_info "WALinuxAgent already installed"
fi

# Configure WALinuxAgent
log_info "Configuring WALinuxAgent..."

WAAGENT_CONF="/etc/waagent.conf"

if [[ -f "$WAAGENT_CONF" ]]; then
    # Backup original config
    cp "$WAAGENT_CONF" "${WAAGENT_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Enable resource disk
    sed -i 's/ResourceDisk.EnableSwap=.*/ResourceDisk.EnableSwap=n/' "$WAAGENT_CONF"
    sed -i 's/ResourceDisk.Format=.*/ResourceDisk.Format=y/' "$WAAGENT_CONF"
    sed -i 's/ResourceDisk.Filesystem=.*/ResourceDisk.Filesystem=ext4/' "$WAAGENT_CONF"
    sed -i 's/ResourceDisk.MountPoint=.*/ResourceDisk.MountPoint=\/mnt\/resource/' "$WAAGENT_CONF"
    
    # Enable verbose logging
    sed -i 's/Logs.Verbose=.*/Logs.Verbose=n/' "$WAAGENT_CONF"
    
    # Enable monitoring
    sed -i 's/Provisioning.MonitorHostName=.*/Provisioning.MonitorHostName=y/' "$WAAGENT_CONF"
    
    log_info "✓ WALinuxAgent configured"
    ((CONFIGS_APPLIED++))
else
    log_warn "WALinuxAgent configuration file not found"
fi

# Enable and start WALinuxAgent
log_info "Enabling WALinuxAgent service..."

systemctl enable waagent
systemctl start waagent &>/dev/null || log_warn "WALinuxAgent failed to start (normal if not on Azure)"

if systemctl is-active --quiet waagent; then
    log_info "✓ WALinuxAgent is running"
else
    log_info "WALinuxAgent service enabled (will start on Azure)"
fi

((CONFIGS_APPLIED++))

# Install cloud-init
log_info "Installing cloud-init..."

if ! rpm -q cloud-init &>/dev/null; then
    if zypper install -y cloud-init; then
        log_info "✓ cloud-init installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install cloud-init"
    fi
else
    log_info "cloud-init already installed"
fi

# Configure cloud-init for Azure
if rpm -q cloud-init &>/dev/null; then
    log_info "Configuring cloud-init for Azure..."
    
    CLOUD_CFG="/etc/cloud/cloud.cfg.d/90-azure.cfg"
    
    cat > "$CLOUD_CFG" <<'EOF'
# Azure Configuration
datasource_list: [ Azure ]
datasource:
  Azure:
    apply_network_config: true
    data_dir: /var/lib/waagent
    dhclient_lease_file: /var/lib/dhcp/dhclient.eth0.leases
    disk_aliases:
      ephemeral0: /dev/disk/cloud/azure_resource
    hostname_bounce:
      interface: eth0
      command: builtin
      policy: true
      hostname_command: hostname
EOF
    
    log_info "✓ cloud-init configured for Azure"
    ((CONFIGS_APPLIED++))
fi

# Install Azure CLI
log_info "Installing Azure CLI..."

if ! command -v az &>/dev/null; then
    # Install Azure CLI
    zypper install -y curl
    
    rpm --import https://packages.microsoft.com/keys/microsoft.asc
    
    zypper addrepo --name 'Azure CLI' --check \
        https://packages.microsoft.com/yumrepos/azure-cli azure-cli
    
    if zypper install -y azure-cli; then
        AZ_VERSION=$(az version --output json 2>/dev/null | grep -o '"azure-cli": "[^"]*"' | cut -d'"' -f4)
        log_info "✓ Azure CLI installed: $AZ_VERSION"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install Azure CLI"
    fi
else
    AZ_VERSION=$(az version --output json 2>/dev/null | grep -o '"azure-cli": "[^"]*"' | cut -d'"' -f4)
    log_info "Azure CLI already installed: $AZ_VERSION"
fi

# Configure network for Azure
log_info "Configuring network settings for Azure..."

# Disable NetworkManager if present (use wicked or systemd-networkd)
if systemctl is-active --quiet NetworkManager; then
    log_info "Disabling NetworkManager (incompatible with Azure agent)..."
    systemctl stop NetworkManager
    systemctl disable NetworkManager
    log_info "✓ NetworkManager disabled"
    ((CONFIGS_APPLIED++))
fi

# Configure DHCP client
DHCP_CONF="/etc/dhcp/dhclient.conf"

if [[ -f "$DHCP_CONF" ]]; then
    if ! grep -q "timeout 300" "$DHCP_CONF"; then
        cat >> "$DHCP_CONF" <<'EOF'

# Azure DHCP Configuration
timeout 300;
retry 60;
EOF
        log_info "✓ DHCP client configured"
        ((CONFIGS_APPLIED++))
    fi
fi

# Configure kernel parameters for Azure
log_info "Configuring kernel parameters for Azure..."

cat > /etc/sysctl.d/90-azure.conf <<'EOF'
# Azure Kernel Configuration
net.ipv4.tcp_timestamps = 0
net.ipv4.conf.all.arp_notify = 1
net.ipv4.conf.default.arp_notify = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_announce = 2
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
EOF

sysctl --system &>/dev/null || log_warn "Failed to apply sysctl settings"

log_info "✓ Kernel parameters configured"
((CONFIGS_APPLIED++))

# Configure udev rules for Azure
log_info "Configuring udev rules for Azure..."

cat > /etc/udev/rules.d/66-azure-storage.rules <<'EOF'
# Azure ephemeral disk rules
KERNEL=="sd*", ATTRS{ID_VENDOR}=="Msft", ATTRS{ID_MODEL}=="Virtual_Disk", GOTO="azure_disk"
GOTO="azure_end"

LABEL="azure_disk"
# Root and data disks
ATTRS{device_id}=="?00000000-0000-*", ENV{fabric_name}="root", GOTO="azure_names"
ATTRS{device_id}=="?00000000-0001-*", ENV{fabric_name}="resource", GOTO="azure_names"
ATTRS{device_id}=="?00000000-0002-*", ENV{fabric_name}="reserved", GOTO="azure_names"

LABEL="azure_names"
ENV{fabric_name}!="", SYMLINK+="disk/azure/$env{fabric_name}"

LABEL="azure_end"
EOF

udevadm control --reload-rules
udevadm trigger

log_info "✓ udev rules configured"
((CONFIGS_APPLIED++))

# Install Hyper-V drivers/tools
log_info "Installing Hyper-V tools..."

if zypper install -y hyperv-daemons; then
    log_info "✓ Hyper-V daemons installed"
    
    # Enable Hyper-V services
    for service in hv-fcopy-daemon hv-kvp-daemon hv-vss-daemon; do
        systemctl enable "$service" 2>/dev/null || true
        systemctl start "$service" &>/dev/null || true
    done
    
    ((CONFIGS_APPLIED++))
else
    log_warn "Failed to install Hyper-V tools"
fi

# Create helper script for Azure metadata
log_info "Creating Azure metadata helper script..."

cat > /usr/local/bin/azure-metadata <<'EOF'
#!/bin/bash
# Azure Instance Metadata Helper Script

API_VERSION="2021-02-01"
curl -s -H Metadata:true \
    "http://169.254.169.254/metadata/instance${1:+/$1}?api-version=${API_VERSION}&format=text"
EOF

chmod +x /usr/local/bin/azure-metadata

log_info "✓ Azure metadata helper created"
((CONFIGS_APPLIED++))

# Verify installations
log_info "Verifying Azure components..."

COMPONENTS_OK=0
COMPONENTS_FAIL=0

if rpm -q WALinuxAgent &>/dev/null || rpm -q python-azure-agent &>/dev/null; then
    log_info "  ✓ WALinuxAgent installed"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ WALinuxAgent not found"
    ((COMPONENTS_FAIL++))
fi

if rpm -q cloud-init &>/dev/null; then
    log_info "  ✓ cloud-init installed"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ cloud-init not found"
    ((COMPONENTS_FAIL++))
fi

if command -v az &>/dev/null; then
    log_info "  ✓ Azure CLI available"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ Azure CLI not found"
    ((COMPONENTS_FAIL++))
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Azure Configuration Summary"
log_info "=============================================="
log_info "Configurations applied: $CONFIGS_APPLIED"
log_info "Components OK: $COMPONENTS_OK"
log_info "Components failed: $COMPONENTS_FAIL"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Azure configuration completed!"
log_info ""
log_info "Installed components:"
log_info "  - WALinuxAgent: $(rpm -q WALinuxAgent --queryformat '%{VERSION}' 2>/dev/null || echo 'not installed')"
log_info "  - cloud-init: $(rpm -q cloud-init --queryformat '%{VERSION}' 2>/dev/null || echo 'not installed')"
log_info "  - Azure CLI: $(az version --output json 2>/dev/null | grep -o '"azure-cli": "[^"]*"' | cut -d'"' -f4 || echo 'not installed')"
log_info ""
log_info "Helper commands:"
log_info "  - Get VM ID: azure-metadata compute/vmId"
log_info "  - Get location: azure-metadata compute/location"
log_info "  - Get VM size: azure-metadata compute/vmSize"