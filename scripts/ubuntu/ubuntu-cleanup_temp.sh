#!/usr/bin/env bash
#
# update_and_upgrade.sh
#
# SYNOPSIS
#   Updates and upgrades Ubuntu packages for Packer image builds
#
# DESCRIPTION
#   Performs a complete system update including:
#   - Package list update
#   - Distribution upgrade
#   - Removal of obsolete packages
#   - Cache cleanup
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges
#   - Internet connectivity
#
# USAGE
#   sudo ./update_and_upgrade.sh

set -Eeuo pipefail
IFS=$'\n\t'

# Configuration
export DEBIAN_FRONTEND=noninteractive
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Ubuntu-Update]"

# APT configuration options
readonly APT_OPTS=(
    -y
    -o Dpkg::Use-Pty=0
    -o Dpkg::Options::="--force-confdef"
    -o Dpkg::Options::="--force-confold"
    -o Acquire::Retries=3
    -o APT::Get::Assume-Yes=true
)

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [INFO] $*"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [WARN] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [ERROR] $*" >&2
}

# Error handler
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Trap errors
trap 'error_exit "Script failed at line $LINENO with exit code $?" "$?"' ERR

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root or with sudo" 1
    fi
}

# Wait for apt/dpkg locks to be released
wait_for_apt_lock() {
    local max_wait=300  # 5 minutes
    local waited=0
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        
        if [[ $waited -ge $max_wait ]]; then
            error_exit "Timeout waiting for apt/dpkg locks to be released" 1
        fi
        
        log_info "Waiting for apt/dpkg locks to be released..."
        sleep 5
        ((waited+=5))
    done
}

# Update package lists
update_package_lists() {
    log_info "Updating package lists..."
    
    if apt-get update "${APT_OPTS[@]}"; then
        log_info "Package lists updated successfully"
        return 0
    else
        log_error "Failed to update package lists"
        return 1
    fi
}

# Perform distribution upgrade
dist_upgrade() {
    log_info "Performing distribution upgrade..."
    log_info "This may take several minutes depending on the number of packages..."
    
    if apt-get dist-upgrade "${APT_OPTS[@]}"; then
        log_info "Distribution upgrade completed successfully"
        return 0
    else
        log_error "Distribution upgrade failed"
        return 1
    fi
}

# Remove obsolete packages
autoremove_packages() {
    log_info "Removing obsolete packages..."
    
    if apt-get autoremove --purge "${APT_OPTS[@]}"; then
        log_info "Obsolete packages removed successfully"
        return 0
    else
        log_warn "Failed to remove some obsolete packages"
        return 1
    fi
}

# Clean package cache
clean_package_cache() {
    log_info "Cleaning package cache..."
    
    local cleaned=0
    
    # Clean downloaded archives
    if apt-get autoclean "${APT_OPTS[@]}"; then
        log_info "Autoclean completed"
        ((cleaned++))
    else
        log_warn "Autoclean failed"
    fi
    
    # Clean all package cache
    if apt-get clean "${APT_OPTS[@]}"; then
        log_info "Clean completed"
        ((cleaned++))
    else
        log_warn "Clean failed"
    fi
    
    if [[ $cleaned -gt 0 ]]; then
        log_info "Package cache cleaned successfully"
        return 0
    else
        log_error "Failed to clean package cache"
        return 1
    fi
}

# Display system information
show_system_info() {
    log_info "System Information:"
    log_info "  OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    log_info "  Kernel: $(uname -r)"
    log_info "  Architecture: $(uname -m)"
}

# Display disk space
show_disk_space() {
    local before=$1
    local after=$2
    local freed=$((before - after))
    
    log_info "Disk space summary:"
    log_info "  Before: $(numfmt --to=iec-i --suffix=B $before 2>/dev/null || echo "${before} bytes")"
    log_info "  After:  $(numfmt --to=iec-i --suffix=B $after 2>/dev/null || echo "${after} bytes")"
    log_info "  Freed:  $(numfmt --to=iec-i --suffix=B $freed 2>/dev/null || echo "${freed} bytes")"
}

# Main execution
main() {
    log_info "=== Starting Ubuntu System Update ==="
    log_info "Script: ${SCRIPT_NAME}"
    
    # Check prerequisites
    check_root
    show_system_info
    
    # Wait for locks if needed
    wait_for_apt_lock
    
    # Get initial disk usage
    local disk_before
    disk_before=$(df / | tail -1 | awk '{print $3}')
    disk_before=$((disk_before * 1024))  # Convert to bytes
    
    # Perform updates
    local steps_completed=0
    local total_steps=4
    
    if update_package_lists; then
        ((steps_completed++))
    else
        error_exit "Failed at step 1/$total_steps: Update package lists" 1
    fi
    
    if dist_upgrade; then
        ((steps_completed++))
    else
        error_exit "Failed at step 2/$total_steps: Distribution upgrade" 1
    fi
    
    if autoremove_packages; then
        ((steps_completed++))
    else
        log_warn "Step 3/$total_steps: Autoremove had issues but continuing..."
        ((steps_completed++))
    fi
    
    if clean_package_cache; then
        ((steps_completed++))
    else
        log_warn "Step 4/$total_steps: Cache cleanup had issues but continuing..."
        ((steps_completed++))
    fi
    
    # Get final disk usage
    local disk_after
    disk_after=$(df / | tail -1 | awk '{print $3}')
    disk_after=$((disk_after * 1024))  # Convert to bytes
    
    # Summary
    log_info "=== Update Summary ==="
    log_info "Steps completed: $steps_completed/$total_steps"
    show_disk_space "$disk_before" "$disk_after"
    
    log_info "Ubuntu system update completed successfully"
    log_info "A reboot may be required if kernel was updated"
    
    # Check if reboot is needed
    if [[ -f /var/run/reboot-required ]]; then
        log_warn "*** System restart required ***"
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            log_info "Packages requiring reboot:"
            while IFS= read -r pkg; do
                log_info "  - $pkg"
            done < /var/run/reboot-required.pkgs
        fi
    fi
}

# Run main function
main "$@"
