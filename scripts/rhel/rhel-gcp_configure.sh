#!/bin/bash
#===================================================================================
# Script: gcp_configure.sh
# Description: Configure Google Cloud Platform settings for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./gcp_configure.sh
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

log_info "Starting GCP configuration..."

# Statistics tracking
START_TIME=$(date +%s)
TASKS_COMPLETED=0
TASKS_FAILED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

#===================================================================================
# Task 1: Add Google Cloud repository
#===================================================================================
log_info "[Task 1/3] Adding Google Cloud repository..."

cat <<'EOF' > /etc/yum.repos.d/google-cloud.repo
[google-cloud-compute]
name=Google Cloud Compute
baseurl=https://packages.cloud.google.com/yum/repos/google-cloud-compute-el8-x86_64-stable
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

log_info "Google Cloud repository added"
TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 2: Install Google Cloud guest agent
#===================================================================================
log_info "[Task 2/3] Installing Google Cloud guest agent..."

if rpm -q google-compute-engine &>/dev/null || rpm -q google-guest-agent &>/dev/null; then
    log_info "Google Cloud guest agent is already installed"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    # Try new package name first
    if $PKG_MGR install -y google-guest-agent 2>&1 | tee -a /tmp/gcp-config.log; then
        log_info "google-guest-agent installed successfully"
        TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    elif $PKG_MGR install -y google-compute-engine 2>&1 | tee -a /tmp/gcp-config.log; then
        log_info "google-compute-engine installed successfully"
        TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    else
        log_warn "Failed to install Google Cloud guest agent"
        TASKS_FAILED=$((TASKS_FAILED + 1))
    fi
fi

# Enable and start guest agent
if systemctl list-unit-files | grep -q "google-guest-agent"; then
    systemctl enable google-guest-agent
    systemctl start google-guest-agent
    log_info "google-guest-agent service enabled and started"
elif systemctl list-unit-files | grep -q "google-accounts-daemon"; then
    systemctl enable google-accounts-daemon
    systemctl start google-accounts-daemon
    log_info "google-accounts-daemon service enabled and started"
fi

#===================================================================================
# Task 3: Install Google Cloud SDK (optional)
#===================================================================================
log_info "[Task 3/3] Installing Google Cloud SDK..."

if command -v gcloud &>/dev/null; then
    log_info "Google Cloud SDK is already installed"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    # Add Cloud SDK repository
    cat <<'EOF' > /etc/yum.repos.d/google-cloud-sdk.repo
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
    
    if $PKG_MGR install -y google-cloud-sdk 2>&1 | tee -a /tmp/gcp-config.log; then
        log_info "Google Cloud SDK installed successfully"
        log_info "gcloud version: $(gcloud version --format='value(Google Cloud SDK)')"
        TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    else
        log_warn "Failed to install Google Cloud SDK"
        TASKS_FAILED=$((TASKS_FAILED + 1))
    fi
fi

# Configure OS Login (if agent is installed)
if rpm -q google-guest-agent &>/dev/null || rpm -q google-compute-engine &>/dev/null; then
    log_info "Configuring OS Login..."
    
    # Enable OS Login in NSS and PAM
    if [[ -f /etc/nsswitch.conf ]]; then
        if ! grep -q "cache_oslogin" /etc/nsswitch.conf; then
            sed -i '/^passwd:/ s/$/ cache_oslogin oslogin/' /etc/nsswitch.conf
            sed -i '/^group:/ s/$/ cache_oslogin oslogin/' /etc/nsswitch.conf
            log_info "OS Login configured in NSS"
        fi
    fi
    
    # Configure SSH for OS Login
    if [[ -f /etc/ssh/sshd_config ]]; then
        if ! grep -q "AuthorizedKeysCommand /usr/bin/google_authorized_keys" /etc/ssh/sshd_config; then
            cat <<'EOF' >> /etc/ssh/sshd_config

# Google Cloud OS Login configuration
AuthorizedKeysCommand /usr/bin/google_authorized_keys
AuthorizedKeysCommandUser root
EOF
            log_info "SSH configured for OS Login"
        fi
    fi
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "GCP Configuration Summary"
log_info "=============================================="
log_info "Tasks completed: $TASKS_COMPLETED/3"
log_info "Tasks failed: $TASKS_FAILED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "GCP configuration completed!"