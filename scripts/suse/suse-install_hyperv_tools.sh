#!/bin/bash
#===================================================================================
# Script: install_hyperv_tools_suse.sh
# Description: Install Hyper-V integration services for SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./install_hyperv_tools_suse.sh
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

log_info "Starting Hyper-V tools installation for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0

# Detect virtualization platform
log_info "Detecting virtualization platform..."
VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "none")

log_info "Detected platform: $VIRT_PLATFORM"

if [[ "$VIRT_PLATFORM" != "microsoft" ]]; then
    log_warn "Not running on Hyper-V platform"
    log_info "Continuing with installation anyway..."
fi

# Install Hyper-V tools
log_info "Installing Hyper-V integration services..."

HYPERV_PACKAGES="hyperv-daemons hyperv-daemons-licenses"

if zypper install -y $HYPERV_PACKAGES; then
    log_info "✓ Hyper-V tools installed"
    ((PACKAGES_INSTALLED++))
else
    log_error "Failed to install Hyper-V tools"
    exit 1
fi

# Get installed versions
for pkg in $HYPERV_PACKAGES; do
    if rpm -q "$pkg" &>/dev/null; then
        VERSION=$(rpm -q "$pkg" --queryformat '%{VERSION}')
        log_info "  $pkg: $VERSION"
    fi
done

# Enable and start Hyper-V services
log_info "Enabling Hyper-V services..."

HYPERV_SERVICES=(
    "hv-fcopy-daemon"
    "hv-kvp-daemon"
    "hv-vss-daemon"
)

for service in "${HYPERV_SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "${service}.service"; then
        systemctl enable "$service"
        systemctl start "$service"
        
        sleep 1
        
        if systemctl is-active --quiet "$service"; then
            log_info "  ✓ $service is running"
        else
            log_warn "  ✗ $service failed to start"
        fi
    else
        log_warn "  - $service not available"
    fi
done

# Check Hyper-V kernel modules
log_info "Checking Hyper-V kernel modules..."

HYPERV_MODULES=(
    "hv_vmbus"
    "hv_storvsc"
    "hv_netvsc"
    "hv_utils"
    "hv_balloon"
)

for module in "${HYPERV_MODULES[@]}"; do
    if lsmod | grep -q "^$module"; then
        log_info "  ✓ $module loaded"
    else
        log_info "  - $module not loaded"
        
        # Try to load the module
        if modprobe "$module" 2>/dev/null; then
            log_info "    ✓ $module loaded successfully"
        else
            log_warn "    ✗ Failed to load $module"
        fi
    fi
done

# Configure automatic module loading
log_info "Configuring automatic module loading..."

cat > /etc/modules-load.d/hyperv.conf <<'EOF'
# Hyper-V modules
hv_vmbus
hv_storvsc
hv_netvsc
hv_utils
hv_balloon
EOF

log_info "✓ Module loading configured"

# Verify KVP (Key-Value Pair) daemon
log_info "Verifying KVP daemon..."

if systemctl is-active --quiet hv-kvp-daemon; then
    log_info "✓ KVP daemon is running"
    
    # Check KVP pools
    if [[ -d /var/lib/hyperv ]]; then
        log_info "  KVP pools directory exists"
        ls -la /var/lib/hyperv/ | while IFS= read -r line; do
            log_info "    $line"
        done
    fi
else
    log_warn "KVP daemon is not running"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

SERVICES_RUNNING=0
for service in "${HYPERV_SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        ((SERVICES_RUNNING++))
    fi
done

log_info "=============================================="
log_info "Hyper-V Tools Installation Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Services running: $SERVICES_RUNNING/${#HYPERV_SERVICES[@]}"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Hyper-V tools installation completed!"
log_info ""
log_info "Service status:"
for service in "${HYPERV_SERVICES[@]}"; do
    STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    log_info "  $service: $STATUS"
done