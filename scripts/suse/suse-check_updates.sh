#!/bin/bash
#===================================================================================
# Script: check_updates_suse.sh
# Description: Check for available system updates on SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./check_updates_suse.sh [--json]
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

# Variables
JSON_OUTPUT="${JSON_OUTPUT:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT="true"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Statistics tracking
START_TIME=$(date +%s)
TOTAL_UPDATES=0
SECURITY_UPDATES=0
KERNEL_UPDATES=0

if [[ "$JSON_OUTPUT" == "false" ]]; then
    log_info "Checking for available updates on SUSE..."
fi

# Update repository metadata
zypper refresh &>/dev/null || log_warn "Failed to refresh repositories"

# Check for all available updates
zypper list-updates &>/tmp/check-updates.log || true

TOTAL_UPDATES=$(grep -c "^v |" /tmp/check-updates.log || echo "0")

# Check for security updates
zypper list-patches --category security &>/tmp/security-updates.log || true
SECURITY_UPDATES=$(grep -c "^Patch" /tmp/security-updates.log || echo "0")

# Check for kernel updates
KERNEL_UPDATES=$(grep -c "kernel-default" /tmp/check-updates.log || echo "0")

# Get current kernel version
CURRENT_KERNEL=$(uname -r)
LATEST_AVAILABLE_KERNEL=$(grep "kernel-default" /tmp/check-updates.log | head -n1 | awk '{print $7}' || echo "$CURRENT_KERNEL")

# Check repository status
REPOS_ENABLED=$(zypper repos --enabled 2>/dev/null | grep -c "^[0-9]" || echo "0")

# Get system information
OS_VERSION=$(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME=" | cut -d'"' -f2 || echo "Unknown")
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')

# Check if reboot is required
REBOOT_REQUIRED=false

if [[ "$KERNEL_UPDATES" -gt 0 ]]; then
    REBOOT_REQUIRED=true
fi

if zypper ps -s 2>/dev/null | grep -q "reboot-required"; then
    REBOOT_REQUIRED=true
fi

# Get last update time
LAST_UPDATE=$(ls -l /var/log/zypp/history 2>/dev/null | awk '{print $6, $7, $8}' || echo "Unknown")

# Output results
if [[ "$JSON_OUTPUT" == "true" ]]; then
    # JSON output for automation
    cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "os_version": "$OS_VERSION",
  "uptime": "$UPTIME",
  "last_update": "$LAST_UPDATE",
  "current_kernel": "$CURRENT_KERNEL",
  "latest_kernel": "$LATEST_AVAILABLE_KERNEL",
  "updates": {
    "total": $TOTAL_UPDATES,
    "security": $SECURITY_UPDATES,
    "kernel": $KERNEL_UPDATES
  },
  "repositories": {
    "enabled": $REPOS_ENABLED
  },
  "reboot_required": $REBOOT_REQUIRED,
  "update_available": $([ "$TOTAL_UPDATES" -gt 0 ] && echo "true" || echo "false")
}
EOF
else
    # Human-readable output
    log_info "=============================================="
    log_info "System Update Check Report"
    log_info "=============================================="
    log_info "System: $OS_VERSION"
    log_info "Uptime: $UPTIME"
    log_info "Last update: $LAST_UPDATE"
    log_info "Current kernel: $CURRENT_KERNEL"
    log_info "Latest kernel: $LATEST_AVAILABLE_KERNEL"
    log_info ""
    log_info "Available Updates:"
    log_info "  Total packages: $TOTAL_UPDATES"
    log_info "  Security patches: $SECURITY_UPDATES"
    log_info "  Kernel updates: $KERNEL_UPDATES"
    log_info ""
    log_info "Repository Status:"
    log_info "  Enabled repositories: $REPOS_ENABLED"
    log_info ""
    log_info "System Status:"
    log_info "  Reboot required: $([ "$REBOOT_REQUIRED" == "true" ] && echo 'Yes' || echo 'No')"
    log_info "=============================================="
    
    # Display detailed package list if updates available
    if [[ "$TOTAL_UPDATES" -gt 0 ]]; then
        log_info ""
        log_info "Available Package Updates (first 30):"
        head -n 30 /tmp/check-updates.log | grep "^v |" | while IFS= read -r line; do
            log_info "  $line"
        done
        
        if [[ "$TOTAL_UPDATES" -gt 30 ]]; then
            log_info "  ... and $((TOTAL_UPDATES - 30)) more"
        fi
        
        # Display security patches
        if [[ "$SECURITY_UPDATES" -gt 0 ]]; then
            log_info ""
            log_info "Security Patches Available:"
            cat /tmp/security-updates.log | grep "^Patch" | head -n 10 | while IFS= read -r line; do
                log_info "  $line"
            done
        fi
        
        # Display recommendations
        log_info ""
        log_info "Recommendations:"
        
        if [[ "$SECURITY_UPDATES" -gt 0 ]]; then
            log_warn "  ⚠ $SECURITY_UPDATES security patches available"
            log_warn "  ⚠ Apply immediately: ./update_system_suse.sh"
        fi
        
        if [[ "$KERNEL_UPDATES" -gt 0 ]]; then
            log_info "  • Kernel updates available"
            log_info "  • Run: ./update_system_suse.sh"
        fi
        
        if [[ "$TOTAL_UPDATES" -gt 0 ]]; then
            log_info "  • Full system update: ./update_system_suse.sh"
            log_info "  • Distribution upgrade: ./update_system_suse.sh --dist-upgrade"
        fi
        
        if [[ "$REBOOT_REQUIRED" == "true" ]]; then
            log_warn "  ⚠ System reboot required"
        fi
    else
        log_info ""
        log_info "✓ System is up to date"
        log_info "✓ No updates available"
    fi
fi

# Exit with appropriate code
if [[ "$TOTAL_UPDATES" -gt 0 ]]; then
    exit 1  # Updates available
else
    exit 0  # No updates
fi