#!/usr/bin/env bash
#
# compliance_report.sh
#
# SYNOPSIS
#   Generates comprehensive system compliance report
#
# DESCRIPTION
#   Creates a detailed report including:
#   - System information
#   - Installed packages
#   - Security configuration
#   - Running services
#   - Firewall rules
#   - And more...
#
# REQUIREMENTS
#   - Ubuntu 24.04 or compatible
#   - Root/sudo privileges (for some checks)

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_PREFIX="[Compliance]"
readonly REPORT_FILE="/tmp/compliance_report_$(date +%Y%m%d-%H%M%S).txt"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [INFO] $*"
}

error_exit() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} [ERROR] $*" >&2
    exit "${2:-1}"
}

# Report section header
report_section() {
    local title="$1"
    {
        echo ""
        echo "========================================"
        echo "  $title"
        echo "========================================"
        echo ""
    } >> "$REPORT_FILE"
}

# Safe command execution
safe_exec() {
    local description="$1"
    shift
    
    report_section "$description"
    if "$@" >> "$REPORT_FILE" 2>&1; then
        return 0
    else
        echo "Command failed or not available" >> "$REPORT_FILE"
        return 1
    fi
}

log_info "=== Starting Compliance Report Generation ==="
log_info "Report file: $REPORT_FILE"

# Initialize report
{
    echo "========================================"
    echo "  SYSTEM COMPLIANCE REPORT"
    echo "========================================"
    echo "Generated: $(date)"
    echo "Hostname: $(hostname)"
    echo "Report by: XOAP Image Management"
    echo "========================================"
} > "$REPORT_FILE"

# System Information
safe_exec "Hostname and OS Information" hostnamectl
safe_exec "OS Release Information" cat /etc/os-release
safe_exec "Kernel Information" uname -a

# Kernel Version
safe_exec "Kernel Version Details" uname -r

# User Information
safe_exec "Current User and Groups" id
safe_exec "All System Groups" getent group
safe_exec "System Users" cat /etc/passwd

# Package Information
safe_exec "Installed DEB Packages" dpkg-query -l
safe_exec "Installed Snap Packages" snap list

# Security Updates
report_section "Security Updates Status"
{
    apt update -qq 2>&1
    apt list --upgradable 2>/dev/null | grep -i security || echo "No security updates available"
} >> "$REPORT_FILE"

# Services
safe_exec "Running Services" systemctl list-units --type=service --state=running --no-pager
safe_exec "All Services Status" systemctl list-unit-files --type=service --no-pager

# Firewall Configuration
safe_exec "UFW Firewall Status" ufw status verbose
safe_exec "iptables Rules (Filter)" iptables -L -n -v
safe_exec "iptables Rules (NAT)" iptables -t nat -L -n -v

# Network
safe_exec "Listening Ports and Services" ss -tulnp
safe_exec "Network Interfaces" ip addr show
safe_exec "Routing Table" ip route show

# Security Modules
safe_exec "AppArmor Status" aa-status
report_section "SELinux Status"
{
    if command -v sestatus &>/dev/null; then
        sestatus
    else
        echo "SELinux not installed (normal for Ubuntu)"
    fi
} >> "$REPORT_FILE"

# Password Policy
safe_exec "Password Policy Configuration" cat /etc/login.defs

# SSH Configuration
safe_exec "SSH Daemon Configuration" cat /etc/ssh/sshd_config

# Sudoers Configuration
safe_exec "Sudoers Main Configuration" cat /etc/sudoers
report_section "Sudoers Drop-in Files"
{
    if ls /etc/sudoers.d/* &>/dev/null; then
        for file in /etc/sudoers.d/*; do
            echo "--- $file ---"
            cat "$file"
            echo ""
        done
    else
        echo "No sudoers drop-in files"
    fi
} >> "$REPORT_FILE"

# Disk Information
safe_exec "Block Devices" lsblk
safe_exec "Disk Usage" df -h
safe_exec "Disk Encryption Status" blkid

# Audit System
report_section "Audit Logs (Last 100 lines)"
{
    if command -v ausearch &>/dev/null; then
        ausearch -ts today 2>/dev/null | tail -100 || echo "No audit logs available"
    else
        echo "Auditd not installed"
    fi
} >> "$REPORT_FILE"

# Scheduled Tasks
safe_exec "User Crontabs" crontab -l
safe_exec "System Cron Jobs" ls -la /etc/cron*

# System Resources
safe_exec "Memory Usage" free -h
safe_exec "CPU Information" lscpu
report_section "System Load and Processes"
{
    uptime
    echo ""
    top -b -n 1 | head -20
} >> "$REPORT_FILE"

# Sysctl Configuration
safe_exec "Kernel Parameters (sysctl)" sysctl -a

# Module Information
safe_exec "Loaded Kernel Modules" lsmod

# File Report
log_info "=== Compliance Report Summary ==="
log_info "Report generated successfully"
log_info "Report location: $REPORT_FILE"
log_info "Report size: $(du -h "$REPORT_FILE" | cut -f1)"
log_info "Lines in report: $(wc -l < "$REPORT_FILE")"

echo ""
echo "========================================="
echo "Report saved to: $REPORT_FILE"
echo "========================================="
