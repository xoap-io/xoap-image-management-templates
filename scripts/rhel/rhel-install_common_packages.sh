#!/bin/bash
#===================================================================================
# Script: install_common_packages.sh
# Description: Install common utility packages for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./install_common_packages.sh
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

log_info "Starting common package installation..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0
PACKAGES_FAILED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

log_info "Using package manager: $PKG_MGR"

# Common utility packages
COMMON_PACKAGES=(
    "vim"
    "nano"
    "wget"
    "curl"
    "git"
    "tmux"
    "screen"
    "htop"
    "iotop"
    "net-tools"
    "bind-utils"
    "traceroute"
    "telnet"
    "nc"
    "rsync"
    "unzip"
    "zip"
    "tar"
    "bzip2"
    "lsof"
    "strace"
    "tcpdump"
    "sysstat"
    "dstat"
    "iftop"
    "nmap-ncat"
)

# Development tools (optional - comment out if not needed)
DEV_PACKAGES=(
    "gcc"
    "make"
    "automake"
    "autoconf"
    "git"
    "patch"
)

# System administration tools
ADMIN_PACKAGES=(
    "bash-completion"
    "man-pages"
    "man-db"
    "which"
    "sudo"
    "psmisc"
    "procps-ng"
)

# Combine all packages
ALL_PACKAGES=("${COMMON_PACKAGES[@]}" "${ADMIN_PACKAGES[@]}")

# Uncomment to include development tools
# ALL_PACKAGES+=("${DEV_PACKAGES[@]}")

log_info "Updating package cache..."
$PKG_MGR makecache

log_info "Installing ${#ALL_PACKAGES[@]} packages..."

for package in "${ALL_PACKAGES[@]}"; do
    # Check if package is already installed
    if rpm -q "$package" &>/dev/null; then
        log_info "Package already installed: $package"
        PACKAGES_INSTALLED=$((PACKAGES_INSTALLED + 1))
        continue
    fi
    
    log_info "Installing: $package"
    
    if $PKG_MGR install -y "$package" 2>&1 | tee -a /tmp/package-install.log; then
        PACKAGES_INSTALLED=$((PACKAGES_INSTALLED + 1))
        log_info "Successfully installed: $package"
    else
        PACKAGES_FAILED=$((PACKAGES_FAILED + 1))
        log_warn "Failed to install: $package"
    fi
done

# Clean package cache
log_info "Cleaning package cache..."
$PKG_MGR clean all

# Verify critical packages
log_info "Verifying critical package installation..."
CRITICAL_PACKAGES=("vim" "wget" "curl" "net-tools")
VERIFICATION_FAILED=0

for package in "${CRITICAL_PACKAGES[@]}"; do
    if rpm -q "$package" &>/dev/null; then
        log_info "✓ $package installed"
    else
        log_warn "✗ $package not installed"
        VERIFICATION_FAILED=$((VERIFICATION_FAILED + 1))
    fi
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Package Installation Summary"
log_info "=============================================="
log_info "Packages processed: ${#ALL_PACKAGES[@]}"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Package failures: $PACKAGES_FAILED"

if [[ $VERIFICATION_FAILED -eq 0 ]]; then
    log_info "All critical packages verified"
else
    log_warn "Verification failures: $VERIFICATION_FAILED"
fi

log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Package installation completed successfully!"