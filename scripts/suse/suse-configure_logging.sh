#!/bin/bash
#===================================================================================
# Script: configure_logging_suse.sh
# Description: Configure centralized logging for SUSE/openSUSE
# Author: XOAP Infrastructure Team
# Usage: ./configure_logging_suse.sh [--remote-host HOST]
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

# Variables
REMOTE_LOG_HOST="${REMOTE_LOG_HOST:-}"
REMOTE_LOG_PORT="${REMOTE_LOG_PORT:-514}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote-host)
            REMOTE_LOG_HOST="$2"
            shift 2
            ;;
        --remote-port)
            REMOTE_LOG_PORT="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting logging configuration for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Configure systemd-journald
log_info "Configuring systemd-journald..."

JOURNALD_CONF="/etc/systemd/journald.conf"

if [[ -f "$JOURNALD_CONF" ]]; then
    # Backup original config
    cp "$JOURNALD_CONF" "${JOURNALD_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Configure journald
    sed -i 's/^#Storage=.*/Storage=persistent/' "$JOURNALD_CONF"
    sed -i 's/^#Compress=.*/Compress=yes/' "$JOURNALD_CONF"
    sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=500M/' "$JOURNALD_CONF"
    sed -i 's/^#SystemMaxFileSize=.*/SystemMaxFileSize=50M/' "$JOURNALD_CONF"
    sed -i 's/^#MaxRetentionSec=.*/MaxRetentionSec=1month/' "$JOURNALD_CONF"
    
    log_info "✓ journald configured"
    ((CONFIGS_APPLIED++))
    
    # Restart journald
    systemctl restart systemd-journald
    log_info "✓ journald restarted"
fi

# Configure rsyslog for remote logging
if [[ -n "$REMOTE_LOG_HOST" ]]; then
    log_info "Configuring rsyslog for remote logging to $REMOTE_LOG_HOST:$REMOTE_LOG_PORT..."
    
    # Install rsyslog if not present
    if ! rpm -q rsyslog &>/dev/null; then
        if zypper install -y rsyslog; then
            log_info "✓ rsyslog installed"
        else
            log_error "Failed to install rsyslog"
            exit 1
        fi
    fi
    
    # Configure remote logging
    cat > /etc/rsyslog.d/50-remote.conf <<EOF
# Remote logging configuration
*.* @@${REMOTE_LOG_HOST}:${REMOTE_LOG_PORT}
EOF
    
    systemctl enable rsyslog
    systemctl restart rsyslog
    
    log_info "✓ rsyslog configured for remote logging"
    ((CONFIGS_APPLIED++))
fi

# Configure log rotation
log_info "Configuring logrotate..."

cat > /etc/logrotate.d/syslog <<'EOF'
/var/log/messages /var/log/secure /var/log/maillog /var/log/cron {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/syslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}
EOF

log_info "✓ logrotate configured"
((CONFIGS_APPLIED++))

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Logging Configuration Summary"
log_info "=============================================="
log_info "journald status: $(systemctl is-active systemd-journald)"
log_info "rsyslog status: $(systemctl is-active rsyslog 2>/dev/null || echo 'not configured')"
log_info "Remote logging: $([ -n "$REMOTE_LOG_HOST" ] && echo "enabled ($REMOTE_LOG_HOST:$REMOTE_LOG_PORT)" || echo 'disabled')"
log_info "Configurations applied: $CONFIGS_APPLIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Logging configuration completed!"