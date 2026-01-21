#!/usr/bin/env bash
#
# remove_snap_packages.sh
#
# SYNOPSIS
#   Removes Snap packages and daemon
#
# DESCRIPTION
#   Completely removes Snap package system to reduce image size
#   and simplify package management
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges

set -Eeuo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Remove-Snap]"

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

log_info "=== Starting Snap Removal ==="

# Check if snapd is installed
if ! command -v snap &>/dev/null; then
    log_info "Snap is not installed, nothing to remove"
    exit 0
fi

# List installed snaps
installed_snaps=$(snap list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

if [[ -n "$installed_snaps" ]]; then
    log_info "Removing installed snap packages..."
    while read -r snap_pkg; do
        log_info "Removing snap: $snap_pkg"
        snap remove --purge "$snap_pkg" 2>/dev/null || log_warn "Failed to remove $snap_pkg"
    done <<< "$installed_snaps"
fi

# Stop snapd services
log_info "Stopping snapd services..."
systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
systemctl disable snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true

# Remove snapd package
log_info "Removing snapd package..."
if apt-get purge snapd -y; then
    log_info "Snapd package removed"
else
    log_warn "Failed to remove snapd package"
fi

# Remove snap directories
log_info "Removing snap directories..."
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd ~/snap 2>/dev/null || true

# Prevent snap from being reinstalled
log_info "Preventing snap reinstallation..."
cat <<EOF > /etc/apt/preferences.d/nosnap.pref
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

log_info "=== Snap Removal Completed ==="
log_info "Snap has been completely removed from the system"
