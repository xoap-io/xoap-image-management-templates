#!/bin/bash
#===================================================================================
# Script: check_updates.sh
# Description: Check for available system updates on RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./check_updates.sh [--security-only] [--json]
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
SECURITY_ONLY="${SECURITY_ONLY:-false}"
JSON_OUTPUT="${JSON_OUTPUT:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --security-only)
            SECURITY_ONLY="true"
            shift
            ;;
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
CRITICAL_UPDATES=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

if [[ "$JSON_OUTPUT" == "false" ]]; then
    log_info "Checking for available updates..."
    log_info "Package manager: $PKG_MGR"
fi

# Update repository metadata
$PKG_MGR makecache &>/dev/null || log_warn "Failed to update repository metadata"

# Check for all available updates
if [[ "$PKG_MGR" == "dnf" ]]; then
    dnf check-update &>/tmp/check-updates.log || true
    
    # Count total updates
    TOTAL_UPDATES=$(grep -E "^[a-zA-Z0-9]" /tmp/check-updates.log | grep -v "^Last metadata" | wc -l || echo "0")
    
    # Count security updates
    dnf updateinfo list security &>/tmp/security-updates.log || true
    SECURITY_UPDATES=$(grep -c "RHSA" /tmp/security-updates.log || echo "0")
    CRITICAL_UPDATES=$(grep -c "Critical" /tmp/security-updates.log || echo "0")
    
    # Count kernel updates
    KERNEL_UPDATES=$(grep -c "^kernel" /tmp/check-updates.log || echo "0")
else
    yum check-update &>/tmp/check-updates.log || true
    
    # Count total updates
    TOTAL_UPDATES=$(grep -E "^[a-zA-Z0-9]" /tmp/check-updates.log | wc -l || echo "0")
    
    # Count security updates
    yum updateinfo list security &>/tmp/security-updates.log || true
    SECURITY_UPDATES=$(grep -c "RHSA" /tmp/security-updates.log || echo "0")
    CRITICAL_UPDATES=$(grep -c "Critical" /tmp/security-updates.log || echo "0")
    
    # Count kernel updates
    KERNEL_UPDATES=$(grep -c "^kernel" /tmp/check-updates.log || echo "0")
fi

# Get current kernel version
CURRENT_KERNEL=$(uname -r)
LATEST_AVAILABLE_KERNEL=$(grep "^kernel" /tmp/check-updates.log | head -n1 | awk '{print $2}' || echo "$CURRENT_KERNEL")

# Check repository status
if [[ "$PKG_MGR" == "dnf" ]]; then
    REPOS_ENABLED=$(dnf repolist enabled 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
else
    REPOS_ENABLED=$(yum repolist enabled 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
fi

# Get system information
OS_VERSION=$(cat /etc/redhat-release 2>/dev/null || echo "Unknown")
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')

# Check if reboot is required
REBOOT_REQUIRED=false

if [[ -f /var/run/reboot-required ]]; then
    REBOOT_REQUIRED=true
elif [[ "$KERNEL_UPDATES" -gt 0 ]]; then
    REBOOT_REQUIRED=true
fi

# Get last update time
if [[ -f /var/log/dnf.log ]]; then
    LAST_UPDATE=$(grep "Complete!" /var/log/dnf.log 2>/dev/null | tail -n1 | awk '{print $1, $2}' || echo "Unknown")
elif [[ -f /var/log/yum.log ]]; then
    LAST_UPDATE=$(tail -n1 /var/log/yum.log 2>/dev/null | awk '{print $1, $2, $3}' || echo "Unknown")
else
    LAST_UPDATE="Unknown"
fi

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
    "critical": $CRITICAL_UPDATES,
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
    log_info "  Security updates: $SECURITY_UPDATES"
    log_info "  Critical updates: $CRITICAL_UPDATES"
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
        if [[ "$SECURITY_ONLY" == "true" ]]; then
            log_info ""
            log_info "Security Updates Available:"
            cat /tmp/security-updates.log | head -n 30 | while IFS= read -r line; do
                log_info "  $line"
            done
        else
            log_info ""
            log_info "Available Package Updates (first 30):"
            head -n 30 /tmp/check-updates.log | grep -E "^[a-zA-Z0-9]" | while IFS= read -r line; do
                log_info "  $line"
            done
            
            if [[ "$TOTAL_UPDATES" -gt 30 ]]; then
                log_info "  ... and $((TOTAL_UPDATES - 30)) more"
            fi
        fi
        
        # Display recommendations
        log_info ""
        log_info "Recommendations:"
        
        if [[ "$CRITICAL_UPDATES" -gt 0 ]]; then
            log_warn "  ⚠ $CRITICAL_UPDATES critical security updates available"
            log_warn "  ⚠ Apply immediately: ./update_system.sh --security-only"
        elif [[ "$SECURITY_UPDATES" -gt 0 ]]; then
            log_info "  • Security updates available"
            log_info "  • Run: ./update_system.sh --security-only"
        fi
        
        if [[ "$KERNEL_UPDATES" -gt 0 ]]; then
            log_info "  • Kernel updates available"
            log_info "  • Run: ./update_system.sh --kernel"
        fi
        
        if [[ "$TOTAL_UPDATES" -gt 0 ]]; then
            log_info "  • Full system update: ./update_system.sh"
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