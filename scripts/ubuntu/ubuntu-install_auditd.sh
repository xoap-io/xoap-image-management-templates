#!/bin/bash
#===================================================================================
# Script: install_auditd_ubuntu.sh
# Description: Install and configure auditd for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./install_auditd_ubuntu.sh
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

log_info "Starting auditd installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
RULES_CONFIGURED=0

# Update package lists
apt-get update -qq

# Install auditd
log_info "Installing auditd..."

if ! dpkg -l | grep -q "^ii.*auditd"; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y auditd audispd-plugins; then
        log_info "✓ auditd installed"
    else
        log_error "Failed to install auditd"
        exit 1
    fi
else
    log_info "auditd already installed"
fi

# Configure auditd
log_info "Configuring auditd rules..."

AUDIT_RULES="/etc/audit/rules.d/hardening.rules"

cat > "$AUDIT_RULES" <<'EOF'
# Audit Rules for Security Monitoring

# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode (0=silent 1=printk 2=panic)
-f 1

# Audit system calls
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change

# Audit user/group modifications
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Audit network configuration
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# Audit login/logout events
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Audit session initiation
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# Audit permission modifications
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod

# Audit unauthorized file access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access

# Audit privileged commands
-a always,exit -F path=/usr/bin/passwd -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-passwd
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-sudo
-a always,exit -F path=/usr/bin/su -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-su

# Audit file deletions
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

# Audit kernel module loading
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# Make configuration immutable
-e 2
EOF

log_info "✓ Audit rules configured"
((RULES_CONFIGURED++))

# Load audit rules
log_info "Loading audit rules..."

augenrules --load

log_info "✓ Audit rules loaded"

# Enable and start auditd
log_info "Enabling auditd service..."

systemctl enable auditd
systemctl restart auditd

if systemctl is-active --quiet auditd; then
    log_info "✓ auditd service is running"
else
    log_error "auditd service failed to start"
    exit 1
fi

# Display audit status
log_info "Audit status:"
auditctl -s | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

LOADED_RULES=$(auditctl -l | wc -l)

log_info "=============================================="
log_info "Auditd Installation Summary"
log_info "=============================================="
log_info "Service status: $(systemctl is-active auditd)"
log_info "Loaded rules: $LOADED_RULES"
log_info "Rules configured: $RULES_CONFIGURED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Auditd installation completed!"
log_info ""
log_info "Useful commands:"
log_info "  - View audit log: ausearch -ts recent"
log_info "  - Generate report: aureport"
log_info "  - List rules: auditctl -l"