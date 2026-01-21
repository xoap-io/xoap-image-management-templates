#!/usr/bin/env bash
#
# hyperv_ubuntu.sh
#
# SYNOPSIS
#   Installs Hyper-V integration packages
#
# DESCRIPTION
#   Installs necessary packages for running Ubuntu on Hyper-V:
#   - linux-image-virtual
#   - linux-tools-virtual  
#   - linux-cloud-tools-virtual
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges
#   - Hyper-V environment

set -Eeuo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Hyper-V]"

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

# Check if running on Hyper-V
if [[ -n "${PACKER_BUILDER_TYPE:-}" ]] && [[ "${PACKER_BUILDER_TYPE}" != "hyperv-iso" ]]; then
    log_info "Not running on Hyper-V (builder: ${PACKER_BUILDER_TYPE}), skipping"
    exit 0
fi

log_info "=== Starting Hyper-V Integration Setup ==="

# Packages to install
packages=(
    "linux-image-virtual"
    "linux-tools-virtual"
    "linux-cloud-tools-virtual"
)

log_info "Installing Hyper-V integration packages..."
log_info "Packages: ${packages[*]}"

if apt-get install -y "${packages[@]}"; then
    log_info "Hyper-V integration packages installed successfully"
else
    error_exit "Failed to install Hyper-V integration packages" 1
fi

# Verify installation
log_info "Verifying installation..."
for pkg in "${packages[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg"; then
        log_info "  ✓ $pkg installed"
    else
        log_warn "  ✗ $pkg not found"
    fi
done

log_info "=== Hyper-V Integration Setup Completed ==="
log_info "A reboot is recommended to load new kernel modules"
