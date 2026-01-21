#!/bin/bash
#===================================================================================
# Script: gcp_configure_ubuntu.sh
# Description: Configure Ubuntu for Google Cloud Platform
# Author: XOAP Infrastructure Team
# Usage: ./gcp_configure_ubuntu.sh
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

log_info "Starting GCP configuration for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Detect if running on GCP
log_info "Detecting cloud platform..."

if curl -s -H "Metadata-Flavor: Google" -m 2 http://metadata.google.internal/computeMetadata/v1/ &>/dev/null; then
    log_info "Running on Google Cloud Platform"
else
    log_warn "Not running on GCP - some features may not work"
fi

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Add Google Cloud repository
log_info "Adding Google Cloud repository..."

if [[ ! -f /etc/apt/sources.list.d/google-cloud-sdk.list ]]; then
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
        tee /etc/apt/sources.list.d/google-cloud-sdk.list
    
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
        gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    
    apt-get update -qq
    
    log_info "✓ Google Cloud repository added"
    ((CONFIGS_APPLIED++))
fi

# Install Google Cloud SDK
log_info "Installing Google Cloud SDK..."

if ! command -v gcloud &>/dev/null; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-sdk; then
        GCLOUD_VERSION=$(gcloud version 2>/dev/null | grep "Google Cloud SDK" | awk '{print $4}')
        log_info "✓ Google Cloud SDK installed: $GCLOUD_VERSION"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install Google Cloud SDK"
    fi
else
    GCLOUD_VERSION=$(gcloud version 2>/dev/null | grep "Google Cloud SDK" | awk '{print $4}')
    log_info "Google Cloud SDK already installed: $GCLOUD_VERSION"
fi

# Install Google Guest Agent
log_info "Installing Google Guest Agent..."

if ! dpkg -l | grep -q "^ii.*google-guest-agent"; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y google-guest-agent; then
        log_info "✓ Google Guest Agent installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install Google Guest Agent"
    fi
else
    log_info "Google Guest Agent already installed"
fi

# Enable and start guest agent
if dpkg -l | grep -q "^ii.*google-guest-agent"; then
    systemctl enable google-guest-agent
    systemctl start google-guest-agent &>/dev/null || log_warn "Guest agent failed to start (normal if not on GCP)"
    
    if systemctl is-active --quiet google-guest-agent; then
        log_info "✓ Google Guest Agent is running"
    else
        log_info "Guest agent service enabled (will start on GCP)"
    fi
fi

# Install OS Login
log_info "Installing Google OS Login..."

if ! dpkg -l | grep -q "^ii.*google-compute-engine-oslogin"; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y google-compute-engine-oslogin; then
        log_info "✓ OS Login installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install OS Login"
    fi
else
    log_info "OS Login already installed"
fi

# Configure OS Login
if dpkg -l | grep -q "^ii.*google-compute-engine-oslogin"; then
    log_info "Configuring OS Login..."
    
    # Add to NSS
    if ! grep -q "google_oslogin" /etc/nsswitch.conf; then
        sed -i '/^passwd:/s/$/ google_oslogin/' /etc/nsswitch.conf
        sed -i '/^group:/s/$/ google_oslogin/' /etc/nsswitch.conf
        log_info "✓ OS Login added to NSS"
        ((CONFIGS_APPLIED++))
    fi
fi

# Install cloud-init
log_info "Installing cloud-init..."

if ! dpkg -l | grep -q "^ii.*cloud-init"; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-init; then
        log_info "✓ cloud-init installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install cloud-init"
    fi
else
    log_info "cloud-init already installed"
fi

# Configure cloud-init for GCP
if dpkg -l | grep -q "^ii.*cloud-init"; then
    log_info "Configuring cloud-init for GCP..."
    
    CLOUD_CFG="/etc/cloud/cloud.cfg.d/90-gcp.cfg"
    
    cat > "$CLOUD_CFG" <<'EOF'
# GCP Configuration
datasource_list: [ GCE ]
datasource:
  GCE:
    retries: 5
    sec_between_retries: 1

system_info:
  default_user:
    name: ubuntu
    lock_passwd: true
    gecos: Ubuntu
    groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
EOF
    
    log_info "✓ cloud-init configured for GCP"
    ((CONFIGS_APPLIED++))
    
    # Clean cloud-init
    cloud-init clean --logs --seed
fi

# Configure network for GCP
log_info "Configuring network settings for GCP..."

cat > /etc/sysctl.d/90-gcp.conf <<'EOF'
# GCP Kernel Configuration
net.ipv4.ip_forward = 1
net.ipv4.tcp_mtu_probing = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl --system &>/dev/null || log_warn "Failed to apply sysctl settings"

log_info "✓ Kernel parameters configured"
((CONFIGS_APPLIED++))

# Install Google Cloud Operations Agent
log_info "Installing Google Cloud Operations Agent..."

if ! systemctl list-unit-files | grep -q "google-cloud-ops-agent"; then
    cd /tmp
    
    if curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh; then
        bash add-google-cloud-ops-agent-repo.sh --also-install
        
        if systemctl list-unit-files | grep -q "google-cloud-ops-agent"; then
            log_info "✓ Operations Agent installed"
            ((CONFIGS_APPLIED++))
        else
            log_warn "Operations Agent installation may have failed"
        fi
        
        rm -f add-google-cloud-ops-agent-repo.sh
    else
        log_warn "Failed to download Operations Agent installer"
    fi
else
    log_info "Operations Agent already installed"
fi

# Create helper script for GCP metadata
log_info "Creating GCP metadata helper script..."

cat > /usr/local/bin/gcp-metadata <<'EOF'
#!/bin/bash
# GCP Instance Metadata Helper Script

curl -s -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/${1}"
EOF

chmod +x /usr/local/bin/gcp-metadata

log_info "✓ GCP metadata helper created"
((CONFIGS_APPLIED++))

# Verify installations
log_info "Verifying GCP components..."

COMPONENTS_OK=0
COMPONENTS_FAIL=0

if command -v gcloud &>/dev/null; then
    log_info "  ✓ Google Cloud SDK available"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ Google Cloud SDK not found"
    ((COMPONENTS_FAIL++))
fi

if dpkg -l | grep -q "^ii.*google-guest-agent"; then
    log_info "  ✓ Google Guest Agent installed"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ Google Guest Agent not found"
    ((COMPONENTS_FAIL++))
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "GCP Configuration Summary"
log_info "=============================================="
log_info "Configurations applied: $CONFIGS_APPLIED"
log_info "Components OK: $COMPONENTS_OK"
log_info "Components failed: $COMPONENTS_FAIL"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "GCP configuration completed!"
log_info ""
log_info "Helper commands:"
log_info "  - Get instance ID: gcp-metadata instance/id"
log_info "  - Get zone: gcp-metadata instance/zone"
log_info "  - Get project ID: gcp-metadata project/project-id"