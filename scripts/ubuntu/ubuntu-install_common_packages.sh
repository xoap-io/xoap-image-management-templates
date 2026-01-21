#!/bin/bash
#===================================================================================
# Script: ubuntu-install_common_packages.sh
# Description: Install common packages for Ubuntu systems
# Author: XOAP Infrastructure Team
# Usage: ./ubuntu-install_common_packages.sh
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

log_info "Starting common packages installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0
PACKAGES_FAILED=0

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Define package categories
COMMON_PACKAGES=(
    # Essential utilities
    "vim"
    "nano"
    "wget"
    "curl"
    "git"
    "rsync"
    "unzip"
    "zip"
    "tar"
    "gzip"
    "bzip2"
    "xz-utils"
    
    # Network utilities
    "net-tools"
    "iproute2"
    "iputils-ping"
    "dnsutils"
    "traceroute"
    "nmap"
    "tcpdump"
    "telnet"
    "netcat-openbsd"
    
    # System utilities
    "htop"
    "iotop"
    "sysstat"
    "lsof"
    "strace"
    "psmisc"
    "procps"
    
    # Security
    "ca-certificates"
    "gnupg"
    "software-properties-common"
    "apt-transport-https"
    
    # File systems
    "nfs-common"
    "cifs-utils"
    
    # System admin tools
    "sudo"
    "bash-completion"
    "man-db"
    "manpages"
    "tree"
    "screen"
    "tmux"
)

# Development tools (optional)
DEV_PACKAGES=(
    "build-essential"
    "gcc"
    "g++"
    "make"
    "automake"
    "autoconf"
    "libtool"
    "pkg-config"
    "git"
    "patch"
    "diffutils"
)

# Combine all packages
ALL_PACKAGES=("${COMMON_PACKAGES[@]}")

# Uncomment to include development tools
# ALL_PACKAGES+=("${DEV_PACKAGES[@]}")

log_info "Installing ${#ALL_PACKAGES[@]} packages..."

# Install packages one by one to track failures
for package in "${ALL_PACKAGES[@]}"; do
    # Check if package is already installed
    if dpkg -l | grep -q "^ii  $package "; then
        log_info "  ○ $package already installed"
        continue
    fi
    
    log_info "  Installing $package..."
    
    if DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" &>/tmp/apt-install-${package}.log; then
        log_info "    ✓ Installed $package"
        ((PACKAGES_INSTALLED++))
    else
        log_warn "    ✗ Failed to install $package"
        ((PACKAGES_FAILED++))
        tail -n 5 /tmp/apt-install-${package}.log | while IFS= read -r line; do
            log_warn "      $line"
        done
    fi
done

# Verify critical packages
log_info "Verifying critical packages..."

CRITICAL_PACKAGES=(
    "vim"
    "curl"
    "wget"
    "net-tools"
    "sudo"
)

VERIFICATION_PASSED=0
VERIFICATION_FAILED=0

for package in "${CRITICAL_PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  $package "; then
        VERSION=$(dpkg -l "$package" | grep "^ii" | awk '{print $3}')
        log_info "  ✓ $package ($VERSION)"
        ((VERIFICATION_PASSED++))
    else
        log_warn "  ✗ $package not installed"
        ((VERIFICATION_FAILED++))
    fi
done

# Clean package cache
log_info "Cleaning package cache..."
apt-get clean
apt-get autoremove -y &>/dev/null || log_warn "Autoremove reported issues"

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Common Packages Installation Summary"
log_info "=============================================="
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Packages failed: $PACKAGES_FAILED"
log_info "Verification passed: $VERIFICATION_PASSED"
log_info "Verification failed: $VERIFICATION_FAILED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="

if [[ $VERIFICATION_FAILED -gt 0 ]]; then
    log_warn "Some critical packages failed to install"
    exit 1
fi

log_info "Common packages installation completed successfully!"