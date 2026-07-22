#!/bin/bash
#===================================================================================
# Script: install_monitoring_agents.sh
# Description: Install monitoring agents for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./install_monitoring_agents.sh
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

log_info "Starting monitoring agent installation..."

# Statistics tracking
START_TIME=$(date +%s)
AGENTS_INSTALLED=0
AGENTS_FAILED=0

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
# Install Prometheus Node Exporter
#===================================================================================
install_node_exporter() {
    log_info "Installing Prometheus Node Exporter..."
    
    NODE_EXPORTER_VERSION="1.7.0"
    NODE_EXPORTER_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    
    # Download and extract
    cd /tmp
    if wget "$NODE_EXPORTER_URL" 2>&1 | tee -a /tmp/node-exporter-install.log; then
        tar -xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
        
        # Install binary
        cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
        chmod +x /usr/local/bin/node_exporter
        
        # Create systemd service
        cat <<'EOF' > /etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
        
        # Enable and start service
        systemctl daemon-reload
        systemctl enable node_exporter
        systemctl start node_exporter
        
        log_info "Node Exporter installed successfully"
        AGENTS_INSTALLED=$((AGENTS_INSTALLED + 1))
        
        # Cleanup
        rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*
    else
        log_warn "Failed to install Node Exporter"
        AGENTS_FAILED=$((AGENTS_FAILED + 1))
    fi
}

#===================================================================================
# Install Telegraf
#===================================================================================
install_telegraf() {
    log_info "Installing Telegraf..."
    
    # Add InfluxData repository
    cat <<'EOF' > /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository - RHEL
baseurl = https://repos.influxdata.com/rhel/\$releasever/\$basearch/stable/
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdb.key
EOF
    
    if $PKG_MGR install -y telegraf 2>&1 | tee -a /tmp/telegraf-install.log; then
        # Enable service (don't start until configured)
        systemctl enable telegraf
        
        log_info "Telegraf installed successfully"
        log_info "Configure /etc/telegraf/telegraf.conf before starting"
        AGENTS_INSTALLED=$((AGENTS_INSTALLED + 1))
    else
        log_warn "Failed to install Telegraf"
        AGENTS_FAILED=$((AGENTS_FAILED + 1))
    fi
}

#===================================================================================
# Install CloudWatch Agent (AWS)
#===================================================================================
install_cloudwatch_agent() {
    log_info "Installing AWS CloudWatch Agent..."
    
    CLOUDWATCH_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm"
    
    if $PKG_MGR install -y "$CLOUDWATCH_URL" 2>&1 | tee -a /tmp/cloudwatch-install.log; then
        log_info "CloudWatch Agent installed successfully"
        log_info "Configure with: /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard"
        AGENTS_INSTALLED=$((AGENTS_INSTALLED + 1))
    else
        log_warn "Failed to install CloudWatch Agent"
        AGENTS_FAILED=$((AGENTS_FAILED + 1))
    fi
}

# Main installation menu
log_info "Available monitoring agents:"
log_info "  1. Prometheus Node Exporter"
log_info "  2. Telegraf"
log_info "  3. AWS CloudWatch Agent"
log_info "  4. All of the above"

# For automation, install all by default
INSTALL_CHOICE="${1:-4}"

case $INSTALL_CHOICE in
    1)
        install_node_exporter
        ;;
    2)
        install_telegraf
        ;;
    3)
        install_cloudwatch_agent
        ;;
    4)
        install_node_exporter
        install_telegraf
        install_cloudwatch_agent
        ;;
    *)
        log_warn "Invalid choice: $INSTALL_CHOICE"
        log_info "Installing Node Exporter only (default)"
        install_node_exporter
        ;;
esac

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Monitoring Agent Installation Summary"
log_info "=============================================="
log_info "Agents installed: $AGENTS_INSTALLED"
log_info "Installation failures: $AGENTS_FAILED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="

if [[ $AGENTS_INSTALLED -gt 0 ]]; then
    log_info "Monitoring agent installation completed!"
else
    log_warn "No monitoring agents were installed"
fi