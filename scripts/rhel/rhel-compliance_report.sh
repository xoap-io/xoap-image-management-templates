#!/bin/bash
#===================================================================================
# Script: compliance_report.sh
# Description: Generate comprehensive compliance report for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./compliance_report.sh
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

log_info "Starting compliance report generation..."

# Configuration
REPORT_DIR="/root/compliance_reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="${REPORT_DIR}/compliance_report_${TIMESTAMP}.txt"
START_TIME=$(date +%s)
SECTIONS_COMPLETED=0
SECTIONS_FAILED=0

# Create report directory
mkdir -p "$REPORT_DIR"

# Function to add section to report
add_section() {
    local section_title="$1"
    local command="$2"
    
    log_info "Collecting: $section_title"
    
    {
        echo ""
        echo "========================================================================"
        echo " $section_title"
        echo "========================================================================"
        echo "Generated: $(date +'%Y-%m-%d %H:%M:%S')"
        echo ""
    } >> "$REPORT"
    
    if eval "$command" >> "$REPORT" 2>&1; then
        SECTIONS_COMPLETED=$((SECTIONS_COMPLETED + 1))
    else
        echo "ERROR: Failed to collect data for this section" >> "$REPORT"
        log_warn "Failed to collect: $section_title"
        SECTIONS_FAILED=$((SECTIONS_FAILED + 1))
    fi
}

# Initialize report header
{
    echo "========================================================================"
    echo " RHEL/CENTOS SYSTEM COMPLIANCE AND SECURITY REPORT"
    echo "========================================================================"
    echo "Generated: $(date +'%Y-%m-%d %H:%M:%S')"
    echo "Hostname: $(hostname)"
    echo "Report File: $REPORT"
    echo "========================================================================"
} > "$REPORT"

# System Information
add_section "OS Release Information" "cat /etc/redhat-release"
add_section "Kernel Information" "uname -a"
add_section "Kernel Version" "uname -r"
add_section "System Architecture" "uname -m"
add_section "CPU Information" "lscpu"
add_section "Memory Information" "free -h"
add_section "System Uptime" "uptime"

# User and Group Information
add_section "Current User and Groups" "id"
add_section "All Groups" "getent group"
add_section "System Users" "cat /etc/passwd"
add_section "Sudo Users" "getent group wheel"
add_section "Recent Logins" "last -20"
add_section "Failed Login Attempts" "lastb -20 2>/dev/null || echo 'No failed login records'"

# Package Management
add_section "Installed Packages (RPM)" "rpm -qa | sort"
add_section "Package Count" "rpm -qa | wc -l && echo 'packages installed'"
add_section "Recently Installed Packages" "rpm -qa --last | head -20"

# Security Updates
add_section "Available Updates" "yum check-update 2>&1 || dnf check-update 2>&1 || echo 'No updates available'"
add_section "Security Updates" "yum updateinfo list security 2>&1 || dnf updateinfo list security 2>&1 || echo 'No security updates'"
add_section "Reboot Required" "needs-restarting -r 2>/dev/null || echo 'needs-restarting not available'"

# Services
add_section "Running Services" "systemctl list-units --type=service --state=running --no-pager"
add_section "Failed Services" "systemctl list-units --type=service --state=failed --no-pager"
add_section "Enabled Services" "systemctl list-unit-files --type=service --state=enabled --no-pager"
add_section "Disabled Services" "systemctl list-unit-files --type=service --state=disabled --no-pager | head -50"

# Network Security
add_section "Firewalld Status" "firewall-cmd --state && firewall-cmd --list-all 2>/dev/null || echo 'Firewalld not active'"
add_section "IPTables Rules" "iptables -L -n -v"
add_section "IP6Tables Rules" "ip6tables -L -n -v"

# Network Configuration
add_section "Network Interfaces" "ip addr show"
add_section "Routing Table" "ip route show"
add_section "Listening Ports" "ss -tulnp"
add_section "Active Connections" "ss -tupn"
add_section "DNS Configuration" "cat /etc/resolv.conf"

# SELinux Status
add_section "SELinux Status" "sestatus"
add_section "SELinux Mode" "getenforce"
add_section "Recent SELinux Denials" "ausearch -m avc -ts recent 2>/dev/null | head -50 || echo 'No recent denials'"

# Security Configuration
add_section "Password Policy" "cat /etc/login.defs"
add_section "PAM Configuration" "ls -la /etc/pam.d/"
add_section "SSH Configuration" "cat /etc/ssh/sshd_config"
add_section "Sudoers Configuration" "cat /etc/sudoers"
add_section "Sudoers.d Files" "ls -la /etc/sudoers.d/ && cat /etc/sudoers.d/* 2>/dev/null || echo 'No custom sudoers files'"

# Kernel Security
add_section "Sysctl Security Settings" "sysctl -a 2>/dev/null | grep -E '(net\.ipv4|kernel\.|fs\.)' | head -100"
add_section "Custom Sysctl Configuration" "cat /etc/sysctl.d/*.conf 2>/dev/null || echo 'No custom sysctl configuration'"

# Disk and Filesystem
add_section "Disk Usage" "df -h"
add_section "Disk Partitions" "lsblk -f"
add_section "Mounted Filesystems" "mount"
add_section "Filesystem Table" "cat /etc/fstab"

# Check for encrypted volumes
add_section "LUKS Encrypted Volumes" "lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINT | grep -i crypt || echo 'No encrypted volumes detected'"

# Audit and Logging
add_section "Audit Daemon Status" "systemctl status auditd --no-pager || echo 'auditd not installed'"
add_section "Audit Rules" "auditctl -l 2>/dev/null || echo 'No audit rules configured'"
add_section "Recent Audit Events" "ausearch -ts recent 2>/dev/null | head -100 || echo 'No recent audit events'"
add_section "System Log Size" "du -sh /var/log/"
add_section "Recent Journal Entries" "journalctl -n 50 --no-pager"
add_section "Journal Disk Usage" "journalctl --disk-usage"

# Scheduled Tasks
add_section "Root Crontab" "crontab -l 2>/dev/null || echo 'No crontab for root'"
add_section "System Cron Jobs" "ls -la /etc/cron.* 2>/dev/null"
add_section "Systemd Timers" "systemctl list-timers --all --no-pager"

# Resource Usage
add_section "Memory Details" "free -h"
add_section "Swap Usage" "swapon --show || echo 'No swap configured'"
add_section "Top CPU Consumers" "ps aux --sort=-%cpu | head -20"
add_section "Top Memory Consumers" "ps aux --sort=-%mem | head -20"
add_section "Load Average" "uptime"
add_section "Process Count" "ps aux | wc -l && echo 'total processes'"

# Kernel Modules
add_section "Loaded Kernel Modules" "lsmod | head -50"
add_section "Module Blacklist" "cat /etc/modprobe.d/* 2>/dev/null || echo 'No module configuration'"

# File Permissions
add_section "SUID Files" "find / -perm -4000 -type f 2>/dev/null | head -50"
add_section "SGID Files" "find / -perm -2000 -type f 2>/dev/null | head -50"
add_section "World-Writable Files" "find / -perm -002 -type f 2>/dev/null | head -50"

# Red Hat Subscription (if applicable)
add_section "Subscription Status" "subscription-manager status 2>/dev/null || echo 'Not registered with Red Hat'"
add_section "Subscriptions" "subscription-manager list --consumed 2>/dev/null || echo 'No subscription data'"

# Summary footer
{
    echo ""
    echo "========================================================================"
    echo " REPORT GENERATION SUMMARY"
    echo "========================================================================"
    echo "Sections completed: $SECTIONS_COMPLETED"
    echo "Sections failed: $SECTIONS_FAILED"
    echo "Report location: $REPORT"
    echo "Report size: $(du -h "$REPORT" | awk '{print $1}')"
    echo "Generated: $(date +'%Y-%m-%d %H:%M:%S')"
    echo "========================================================================"
} >> "$REPORT"

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Display summary
log_info "=============================================="
log_info "Compliance Report Summary"
log_info "=============================================="
log_info "Sections completed: $SECTIONS_COMPLETED"
log_info "Sections failed: $SECTIONS_FAILED"
log_info "Report location: $REPORT"
log_info "Report size: $(du -h "$REPORT" | awk '{print $1}')"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Compliance report generated successfully!"
log_info ""
log_info "View report with: less $REPORT"