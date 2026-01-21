#!/bin/bash
#===================================================================================
# Script: azure_configure_ubuntu.sh
# Description: Configure Ubuntu for Microsoft Azure
# Author: XOAP Infrastructure Team
# Usage: ./azure_configure_ubuntu.sh
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

log_info "Starting Azure configuration for Ubuntu..."

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

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Install WALinuxAgent
log_info "Installing WALinuxAgent..."

if ! dpkg -l | grep -q "^ii.*walinuxagent"; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y walinuxagent; then
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
    cp "$WAAGENT_CONF" "${WAAGENT_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
    
    sed -i 's/ResourceDisk.EnableSwap=.*/ResourceDisk.EnableSwap=n/' "$WAAGENT_CONF"
    sed -i 's/ResourceDisk.Format=.*/ResourceDisk.Format=y/' "$WAAGENT_CONF"
    sed -i 's/ResourceDisk.Filesystem=.*/ResourceDisk.Filesystem=ext4/' "$WAAGENT_CONF"
    sed -i 's/ResourceDisk.MountPoint=.*/ResourceDisk.MountPoint=\/mnt/' "$WAAGENT_CONF"
    sed -i 's/Logs.Verbose=.*/Logs.Verbose=n/' "$WAAGENT_CONF"
    sed -i 's/Provisioning.MonitorHostName=.*/Provisioning.MonitorHostName=y/' "$WAAGENT_CONF"
    
    log_info "✓ WALinuxAgent configured"
    ((CONFIGS_APPLIED++))
fi

# Enable and start WALinuxAgent
systemctl enable walinuxagent
systemctl start walinuxagent &>/dev/null || log_warn "WALinuxAgent failed to start (normal if not on Azure)"

if systemctl is-active --quiet walinuxagent; then
    log_info "✓ WALinuxAgent is running"
else
    log_info "WALinuxAgent service enabled (will start on Azure)"
fi

((CONFIGS_APPLIED++))

# Install cloud-init
log_info "Installing cloud-init..."

if ! dpkg -l | grep -q "^ii.*cloud-init"; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-init; then
        log_info "✓ cloud-init installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install cloud-init"
    fi
else
    log_info "cloud-init already installed"
fi

# Configure cloud-init for Azure
if dpkg -l | grep -q "^ii.*cloud-init"; then
    log_info "Configuring cloud-init for Azure..."
    
    CLOUD_CFG="/etc/cloud/cloud.cfg.d/90-azure.cfg"
    
    cat > "$CLOUD_CFG" <<'EOF'
# Azure Configuration
datasource_list: [ Azure ]
datasource:
  Azure:
    apply_network_config: true
    data_dir: /var/lib/waagent
    disk_aliases:
      ephemeral0: /dev/disk/cloud/azure_resource
EOF
    
    log_info "✓ cloud-init configured for Azure"
    ((CONFIGS_APPLIED++))
    
    # Clean cloud-init
    cloud-init clean --logs --seed
fi

# Install Azure CLI
log_info "Installing Azure CLI..."

if ! command -v az &>/dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    
    if command -v az &>/dev/null; then
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

# Configure kernel parameters for Azure
log_info "Configuring kernel parameters for Azure..."

cat > /etc/sysctl.d/90-azure.conf <<'EOF'
# Azure Kernel Configuration
net.ipv4.tcp_timestamps = 0
net.ipv4.conf.all.arp_notify = 1
net.ipv4.conf.default.arp_notify = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF

sysctl --system &>/dev/null || log_warn "Failed to apply sysctl settings"

log_info "✓ Kernel parameters configured"
((CONFIGS_APPLIED++))

# Configure udev rules for Azure
log_info "Configuring udev rules for Azure..."

cat > /etc/udev/rules.d/66-azure-storage.rules <<'EOF'
# Azure ephemeral disk rules
SUBSYSTEM=="block", ATTRS{ID_VENDOR}=="Msft", ATTRS{ID_MODEL}=="Virtual_Disk", GOTO="azure_disk"
GOTO="azure_end"

LABEL="azure_disk"
ATTRS{device_id}=="?00000000-0000-*", ENV{fabric_name}="root", GOTO="azure_names"
ATTRS{device_id}=="?00000000-0001-*", ENV{fabric_name}="resource", GOTO="azure_names"

LABEL="azure_names"
ENV{fabric_name}!="", SYMLINK+="disk/azure/$env{fabric_name}"

LABEL="azure_end"
EOF

udevadm control --reload-rules
udevadm trigger

log_info "✓ udev rules configured"
((CONFIGS_APPLIED++))

# Install Hyper-V tools
log_info "Installing Hyper-V tools..."

if DEBIAN_FRONTEND=noninteractive apt-get install -y linux-tools-virtual linux-cloud-tools-virtual; then
    log_info "✓ Hyper-V tools installed"
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

if dpkg -l | grep -q "^ii.*walinuxagent"; then
    log_info "  ✓ WALinuxAgent installed"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ WALinuxAgent not found"
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
log_info "Helper commands:"
log_info "  - Get VM ID: azure-metadata compute/vmId"
log_info "  - Get location: azure-metadata compute/location"
log_info "  - Get VM size: azure-metadata compute/vmSize"