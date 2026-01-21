#!/bin/bash
#===================================================================================
# Script: install_qemu_agent_ubuntu.sh
# Description: Install QEMU Guest Agent for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./install_qemu_agent_ubuntu.sh
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

log_info "Starting QEMU Guest Agent installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)

# Detect virtualization platform
log_info "Detecting virtualization platform..."
VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "none")

log_info "Detected platform: $VIRT_PLATFORM"

if [[ "$VIRT_PLATFORM" != "kvm" ]] && [[ "$VIRT_PLATFORM" != "qemu" ]]; then
    log_warn "Not running on QEMU/KVM platform"
    log_info "Continuing with installation anyway..."
fi

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Install qemu-guest-agent
log_info "Installing qemu-guest-agent package..."

if dpkg -l | grep -q "^ii.*qemu-guest-agent"; then
    log_info "qemu-guest-agent is already installed"
    AGENT_VERSION=$(dpkg -l qemu-guest-agent | grep '^ii' | awk '{print $3}')
    log_info "Installed version: $AGENT_VERSION"
else
    if DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent; then
        log_info "✓ qemu-guest-agent installed successfully"
        AGENT_VERSION=$(dpkg -l qemu-guest-agent | grep '^ii' | awk '{print $3}')
        log_info "Installed version: $AGENT_VERSION"
    else
        log_error "Failed to install qemu-guest-agent"
        exit 1
    fi
fi

# Enable and start qemu-guest-agent service
log_info "Enabling qemu-guest-agent service..."

systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent

# Wait for service to start
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
log_info "Package version: $(dpkg -l qemu-guest-agent 2>/dev/null | grep '^ii' | awk '{print $3}' || echo 'unknown')"
log_info "Service status: $(systemctl is-active qemu-guest-agent)"
log_info "Service enabled: $(systemctl is-enabled qemu-guest-agent)"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "QEMU Guest Agent installation completed!"