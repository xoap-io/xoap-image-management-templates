#!/usr/bin/env bash
#
# remove_unused_pkgs.sh
#
# SYNOPSIS
#   Removes unused packages and dependencies
#
# DESCRIPTION
#   Cleans up orphaned packages and unused dependencies
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges

set -Eeuo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Remove-Unused]"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [INFO] $*"
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

log_info "=== Starting Unused Package Removal ==="

# Get list of packages that will be removed
unused_count=$(apt-get autoremove --dry-run | grep -c '^Remv' || echo 0)

if [[ $unused_count -eq 0 ]]; then
    log_info "No unused packages found"
    exit 0
fi

log_info "Found $unused_count unused package(s) to remove"

# Get initial disk usage
disk_before=$(df / | tail -1 | awk '{print $3}')

# Remove unused packages
log_info "Removing unused packages..."
if apt-get autoremove -y --purge; then
    log_info "Unused packages removed successfully"
else
    error_exit "Failed to remove unused packages" 1
fi

# Get final disk usage
disk_after=$(df / | tail -1 | awk '{print $3}')
freed=$((disk_before - disk_after))

log_info "=== Removal Summary ==="
log_info "Packages removed: $unused_count"
log_info "Disk space freed: ${freed}KB ($(numfmt --to=iec-i --suffix=B $((freed * 1024)) 2>/dev/null || echo "${freed}KB"))"
log_info "Unused package removal completed"
