#!/bin/bash
#===================================================================================
# Script: install_qemu_agent.sh
# Description: Install QEMU Guest Agent for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./install_qemu_agent.sh
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

log_info "Starting QEMU Guest Agent installation..."

# Statistics tracking
START_TIME=$(date +%s)

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

# Check if running in QEMU/KVM
log_info "Detecting virtualization platform..."
VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "unknown")

log_info "Detected platform: $VIRT_PLATFORM"

if [[ "$VIRT_PLATFORM" != "kvm" ]] && [[ "$VIRT_PLATFORM" != "qemu" ]]; then
    log_warn "Not running on QEMU/KVM platform"
    log_info "Continuing with installation anyway..."
fi

# Install qemu-guest-agent
log_info "Installing qemu-guest-agent package..."

if rpm -q qemu-guest-agent &>/dev/null; then
    log_info "qemu-guest-agent is already installed"
    AGENT_VERSION=$(rpm -q qemu-guest-agent --queryformat '%{VERSION}')
    log_info "Installed version: $AGENT_VERSION"
else
    if $PKG_MGR install -y qemu-guest-agent 2>&1 | tee -a /tmp/qemu-agent-install.log; then
        log_info "qemu-guest-agent installed successfully"
        AGENT_VERSION=$(rpm -q qemu-guest-agent --queryformat '%{VERSION}')
        log_info "Installed version: $AGENT_VERSION"
    else
        log_error "Failed to install qemu-guest-agent"
        exit 1
    fi
fi

# Enable and start qemu-guest-agent service
log_info "Enabling and starting qemu-guest-agent service..."

systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent

# Verify service status
sleep 2

if systemctl is-active --quiet qemu-guest-agent; then
    log_info "✓ qemu-guest-agent service is running"
else
    log_error "✗ qemu-guest-agent service failed to start"
    systemctl status qemu-guest-agent --no-pager
    exit 1
fi

if systemctl is-enabled --quiet qemu-guest-agent; then
    log_info "✓ qemu-guest-agent service is enabled"
fi

# Check virtio-serial device
log_info "Checking for virtio-serial device..."

if [[ -c /dev/virtio-ports/org.qemu.guest_agent.0 ]]; then
    log_info "✓ virtio-serial device found"
elif [[ -c /dev/vport0p1 ]]; then
    log_info "✓ virtio-serial device found (legacy)"
else
    log_warn "✗ virtio-serial device not found"
    log_warn "Guest agent may not function properly"
fi

# Display service status
log_info "Service status:"
systemctl status qemu-guest-agent --no-pager | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "QEMU Guest Agent Installation Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Package version: $(rpm -q qemu-guest-agent --queryformat '%{VERSION}')"
log_info "Service status: $(systemctl is-active qemu-guest-agent)"
log_info "Service enabled: $(systemctl is-enabled qemu-guest-agent)"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "QEMU Guest Agent installation completed!"