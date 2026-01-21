#!/bin/bash
#===================================================================================
# Script: install_common_packages_suse.sh
# Description: Install common utility packages for SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./install_common_packages_suse.sh
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

log_info "Starting common packages installation for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0
PACKAGES_FAILED=0

# Common utility packages
PACKAGES=(
    # System utilities
    "vim"
    "nano"
    "less"
    "which"
    "wget"
    "curl"
    "rsync"
    "tree"
    "screen"
    "tmux"
    
    # Network tools
    "net-tools"
    "iproute2"
    "iputils"
    "bind-utils"
    "traceroute"
    "tcpdump"
    "nmap"
    "telnet"
    
    # System monitoring
    "htop"
    "iotop"
    "sysstat"
    "lsof"
    "strace"
    
    # Compression tools
    "gzip"
    "bzip2"
    "xz"
    "zip"
    "unzip"
    "p7zip"
    
    # Development tools
    "git"
    "make"
    "gcc"
    "gcc-c++"
    "patch"
    "diffutils"
    
    # Security tools
    "openssl"
    "ca-certificates"
    "gnupg2"
    
    # File systems
    "nfs-client"
    "cifs-utils"
    
    # System tools
    "sudo"
    "bash-completion"
    "man"
    "man-pages"
)

log_info "Packages to install: ${#PACKAGES[@]}"

# Refresh repositories
log_info "Refreshing package repositories..."

if zypper refresh 2>&1 | tee /tmp/zypper-refresh.log; then
    log_info "✓ Repositories refreshed"
else
    log_warn "Failed to refresh some repositories"
fi

# Install packages
log_info "Installing packages..."

for package in "${PACKAGES[@]}"; do
    if rpm -q "$package" &>/dev/null; then
        log_info "  ○ $package already installed"
    else
        log_info "  Installing $package..."
        
        if zypper install -y "$package" &>/tmp/zypper-install-${package}.log; then
            log_info "    ✓ Installed $package"
            ((PACKAGES_INSTALLED++))
        else
            log_warn "    ✗ Failed to install $package"
            ((PACKAGES_FAILED++))
            tail -n 5 /tmp/zypper-install-${package}.log | while IFS= read -r line; do
                log_warn "      $line"
            done
        fi
    fi
done

# Verify critical packages
log_info "Verifying critical packages..."

CRITICAL_PACKAGES=(
    "vim"
    "curl"
    "wget"
    "git"
    "sudo"
)

VERIFICATION_PASSED=0
VERIFICATION_FAILED=0

for package in "${CRITICAL_PACKAGES[@]}"; do
    if rpm -q "$package" &>/dev/null; then
        VERSION=$(rpm -q "$package" --queryformat '%{VERSION}')
        log_info "  ✓ $package ($VERSION)"
        ((VERIFICATION_PASSED++))
    else
        log_warn "  ✗ $package not installed"
        ((VERIFICATION_FAILED++))
    fi
done

# Install Python and pip
log_info "Installing Python and pip..."

if ! rpm -q python3 &>/dev/null; then
    if zypper install -y python3 python3-pip; then
        log_info "✓ Python3 and pip installed"
        ((PACKAGES_INSTALLED++))
    else
        log_warn "Failed to install Python3"
    fi
else
    log_info "Python3 already installed"
fi

# Display Python version
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    log_info "Python version: $PYTHON_VERSION"
fi

# Update pip
if command -v pip3 &>/dev/null; then
    log_info "Updating pip..."
    pip3 install --upgrade pip &>/dev/null || log_warn "Failed to upgrade pip"
fi

# Clean up package cache
log_info "Cleaning up package cache..."

zypper clean --all &>/dev/null || log_warn "Failed to clean cache"

# Display installed package count
TOTAL_PACKAGES=$(rpm -qa | wc -l)
log_info "Total packages installed on system: $TOTAL_PACKAGES"

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Package Installation Summary"
log_info "=============================================="
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Packages failed: $PACKAGES_FAILED"
log_info "Verification passed: $VERIFICATION_PASSED"
log_info "Verification failed: $VERIFICATION_FAILED"
log_info "Total system packages: $TOTAL_PACKAGES"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Package installation completed!"