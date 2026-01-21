#!/usr/bin/env bash
#
# cleanup_ubuntu.sh
#
# SYNOPSIS
#   Cleans and minimizes Ubuntu system for imaging
#
# DESCRIPTION
#   Removes unnecessary packages, old kernels, development packages,
#   documentation, and other bloat to minimize image size
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges

set -Eeuo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Cleanup-Ubuntu]"

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

# Safe package removal function
remove_packages() {
    local description="$1"
    shift
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_info "No packages to remove for: $description"
        return 0
    fi
    
    log_info "Removing $description (${#packages[@]} packages)..."
    if apt-get -y purge "${packages[@]}" 2>/dev/null; then
        log_info "$description removed successfully"
        return 0
    else
        log_warn "Failed to remove some $description"
        return 1
    fi
}

log_info "=== Starting Ubuntu System Cleanup ==="
log_info "Current kernel: $(uname -r)"

# Get initial disk usage
disk_before=$(df / | tail -1 | awk '{print $3}')

# Remove linux-headers packages
log_info "Removing Linux header packages..."
headers=($(dpkg --list | awk '/^ii/ { print $2 }' | grep '^linux-headers' || true))
if [[ ${#headers[@]} -gt 0 ]]; then
    remove_packages "Linux headers" "${headers[@]}"
fi

# Remove old Linux kernels (except current)
log_info "Removing old Linux kernel images..."
current_kernel=$(uname -r)
old_kernels=($(dpkg --list | awk '/^ii/ { print $2 }' | grep '^linux-image-.*-generic' | grep -v "$current_kernel" || true))
if [[ ${#old_kernels[@]} -gt 0 ]]; then
    remove_packages "old kernel images" "${old_kernels[@]}"
fi

# Remove old kernel modules (except current)
log_info "Removing old kernel modules..."
old_modules=($(dpkg --list | awk '/^ii/ { print $2 }' | grep '^linux-modules-.*-generic' | grep -v "$current_kernel" || true))
if [[ ${#old_modules[@]} -gt 0 ]]; then
    remove_packages "old kernel modules" "${old_modules[@]}"
fi

# Remove linux-source packages
log_info "Removing Linux source packages..."
sources=($(dpkg --list | awk '/^ii/ { print $2 }' | grep '^linux-source' || true))
if [[ ${#sources[@]} -gt 0 ]]; then
    remove_packages "Linux source" "${sources[@]}"
fi

# Remove development packages
log_info "Removing development packages..."
dev_pkgs=($(dpkg --list | awk '/^ii/ { print $2 }' | grep -- '-dev\(:[a-z0-9]\+\)\?$' || true))
if [[ ${#dev_pkgs[@]} -gt 0 ]]; then
    remove_packages "development packages" "${dev_pkgs[@]}"
fi

# Remove documentation packages
log_info "Removing documentation packages..."
doc_pkgs=($(dpkg --list | awk '/^ii/ { print $2 }' | grep -- '-doc$' || true))
if [[ ${#doc_pkgs[@]} -gt 0 ]]; then
    remove_packages "documentation packages" "${doc_pkgs[@]}"
fi

# Remove X11 libraries
log_info "Removing X11 libraries..."
apt-get -y purge libx11-data xauth libxmuu1 libxcb1 libx11-6 libxext6 2>/dev/null || log_warn "Some X11 packages not found"

# Remove obsolete networking
log_info "Removing obsolete networking packages..."
apt-get -y purge ppp pppconfig pppoeconf 2>/dev/null || log_warn "Some PPP packages not found"

# Remove unnecessary packages
log_info "Removing unnecessary packages..."
unnecessary_pkgs=(
    popularity-contest
    command-not-found
    command-not-found-data
    friendly-recovery
    bash-completion
    laptop-detect
    motd-news-config
    usbutils
    grub-legacy-ec2
    fonts-ubuntu-font-family-console
    fonts-ubuntu-console
    installation-report
)

for pkg in "${unnecessary_pkgs[@]}"; do
    apt-get -y purge "$pkg" 2>/dev/null || true
done

# Autoremove and autoclean
log_info "Removing orphaned packages..."
apt-get -y autoremove --purge

log_info "Cleaning package cache..."
apt-get -y autoclean
apt-get -y clean

# Get final disk usage
disk_after=$(df / | tail -1 | awk '{print $3}')
freed=$((disk_before - disk_after))

log_info "=== Cleanup Summary ==="
log_info "Disk space freed: ${freed}KB ($(numfmt --to=iec-i --suffix=B $((freed * 1024)) 2>/dev/null || echo "${freed}KB"))"
log_info "Ubuntu system cleanup completed"
