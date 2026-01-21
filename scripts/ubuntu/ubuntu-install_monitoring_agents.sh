#!/bin/bash
#===================================================================================
# Script: install_monitoring_agents_ubuntu.sh
# Description: Install monitoring agents for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./install_monitoring_agents_ubuntu.sh [--skip-node-exporter] [--skip-telegraf]
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
INSTALL_NODE_EXPORTER="${INSTALL_NODE_EXPORTER:-true}"
INSTALL_TELEGRAF="${INSTALL_TELEGRAF:-true}"
NODE_EXPORTER_VERSION="1.7.0"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-node-exporter)
            INSTALL_NODE_EXPORTER="false"
            shift
            ;;
        --skip-telegraf)
            INSTALL_TELEGRAF="false"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting monitoring agents installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
AGENTS_INSTALLED=0

# Update package lists
apt-get update -qq

# Install Prometheus Node Exporter
if [[ "$INSTALL_NODE_EXPORTER" == "true" ]]; then
    log_info "Installing Prometheus Node Exporter..."
    
    if ! command -v node_exporter &>/dev/null; then
        cd /tmp
        
        NE_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
        
        if curl -sL -o node_exporter.tar.gz "$NE_URL"; then
            tar xzf node_exporter.tar.gz
            cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
            chmod +x /usr/local/bin/node_exporter
            rm -rf node_exporter.tar.gz "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"
            
            log_info "✓ Node Exporter binary installed"
            
            # Create user
            useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || log_info "  User already exists"
            
            # Create systemd service
            cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=:9100 \
    --collector.systemd \
    --collector.processes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
            
            systemctl daemon-reload
            systemctl enable node_exporter
            systemctl start node_exporter
            
            sleep 2
            
            if systemctl is-active --quiet node_exporter; then
                log_info "✓ Node Exporter is running"
                ((AGENTS_INSTALLED++))
            else
                log_warn "Node Exporter failed to start"
            fi
        else
            log_warn "Failed to download Node Exporter"
        fi
    else
        log_info "Node Exporter already installed"
    fi
fi

# Install Telegraf
if [[ "$INSTALL_TELEGRAF" == "true" ]]; then
    log_info "Installing Telegraf..."
    
    if ! command -v telegraf &>/dev/null; then
        # Add InfluxData repository
        curl -s https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor -o /usr/share/keyrings/influxdata-archive-keyring.gpg
        
        echo "deb [signed-by=/usr/share/keyrings/influxdata-archive-keyring.gpg] https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable" | \
            tee /etc/apt/sources.list.d/influxdata.list
        
        apt-get update -qq
        
        if DEBIAN_FRONTEND=noninteractive apt-get install -y telegraf; then
            log_info "✓ Telegraf installed"
            
            # Basic configuration
            cat > /etc/telegraf/telegraf.conf <<'EOF'
[global_tags]
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false

[[outputs.file]]
  files = ["stdout"]

[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

[[inputs.diskio]]

[[inputs.kernel]]

[[inputs.mem]]

[[inputs.processes]]

[[inputs.swap]]

[[inputs.system]]

[[inputs.net]]

[[inputs.netstat]]
EOF
            
            systemctl enable telegraf
            systemctl start telegraf
            
            sleep 2
            
            if systemctl is-active --quiet telegraf; then
                log_info "✓ Telegraf is running"
                ((AGENTS_INSTALLED++))
            else
                log_warn "Telegraf failed to start"
            fi
        else
            log_warn "Failed to install Telegraf"
        fi
    else
        log_info "Telegraf already installed"
    fi
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Monitoring Agents Installation Summary"
log_info "=============================================="
log_info "Node Exporter: $(systemctl is-active node_exporter 2>/dev/null || echo 'not installed')"
log_info "Telegraf: $(systemctl is-active telegraf 2>/dev/null || echo 'not installed')"
log_info "Agents installed: $AGENTS_INSTALLED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Monitoring agents installation completed!"
log_info ""
log_info "Endpoints:"
log_info "  - Node Exporter: http://localhost:9100/metrics"
log_info "  - Telegraf config: /etc/telegraf/telegraf.conf"