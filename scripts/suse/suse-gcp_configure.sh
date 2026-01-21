#!/bin/bash
#===================================================================================
# Script: gcp_configure_suse.sh
# Description: Configure SUSE/openSUSE for Google Cloud Platform
# Author: XOAP Infrastructure Team
# Usage: ./gcp_configure_suse.sh
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

log_info "Starting GCP configuration for SUSE..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Detect if running on GCP
log_info "Detecting cloud platform..."

if curl -s -H "Metadata-Flavor: Google" -m 2 http://metadata.google.internal/computeMetadata/v1/ &>/dev/null; then
    log_info "Running on Google Cloud Platform"
elif [[ -f /sys/class/dmi/id/product_name ]] && grep -qi "Google" /sys/class/dmi/id/product_name; then
    log_info "GCP detected via DMI"
else
    log_warn "Not running on GCP - some features may not work"
fi

# Install Google Cloud guest environment
log_info "Installing Google Cloud guest environment..."

if ! rpm -q google-compute-engine &>/dev/null; then
    # Add Google Cloud repository
    zypper addrepo --name 'Google Cloud SDK' --check \
        https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64 google-cloud-sdk
    
    # Import Google Cloud public key
    rpm --import https://packages.cloud.google.com/yum/doc/yum-key.gpg
    rpm --import https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    
    # Install guest environment
    if zypper install -y google-compute-engine google-compute-engine-oslogin; then
        log_info "✓ GCP guest environment installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install GCP guest environment"
    fi
else
    log_info "GCP guest environment already installed"
fi

# Install Google Cloud SDK
log_info "Installing Google Cloud SDK..."

if ! command -v gcloud &>/dev/null; then
    if zypper install -y google-cloud-sdk; then
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

if ! systemctl list-unit-files | grep -q "google-guest-agent"; then
    cd /tmp
    
    # Download and install latest guest agent
    GGA_URL="https://github.com/GoogleCloudPlatform/guest-agent/releases/latest/download/google-guest-agent.rpm"
    
    if curl -sL -o google-guest-agent.rpm "$GGA_URL"; then
        if zypper install -y ./google-guest-agent.rpm; then
            log_info "✓ Google Guest Agent installed"
            ((CONFIGS_APPLIED++))
        else
            log_warn "Failed to install Google Guest Agent"
        fi
        rm -f google-guest-agent.rpm
    else
        log_warn "Failed to download Google Guest Agent"
    fi
else
    log_info "Google Guest Agent already installed"
fi

# Enable and start guest agent
if systemctl list-unit-files | grep -q "google-guest-agent"; then
    systemctl enable google-guest-agent
    systemctl start google-guest-agent &>/dev/null || log_warn "Guest agent failed to start (normal if not on GCP)"
    
    if systemctl is-active --quiet google-guest-agent; then
        log_info "✓ Google Guest Agent is running"
    else
        log_info "Guest agent service enabled (will start on GCP)"
    fi
fi

# Install OS Login
log_info "Configuring OS Login..."

if rpm -q google-compute-engine-oslogin &>/dev/null; then
    # Enable OS Login in NSS and PAM
    if ! grep -q "google_oslogin" /etc/nsswitch.conf; then
        sed -i '/^passwd:/s/$/ google_oslogin/' /etc/nsswitch.conf
        sed -i '/^group:/s/$/ google_oslogin/' /etc/nsswitch.conf
        log_info "✓ OS Login added to NSS"
        ((CONFIGS_APPLIED++))
    fi
    
    # Configure PAM for OS Login
    if [[ ! -f /etc/pam.d/google_oslogin ]]; then
        cat > /etc/pam.d/google_oslogin <<'EOF'
#%PAM-1.0
auth       required     pam_oslogin_login.so
account    required     pam_oslogin_admin.so
EOF
        log_info "✓ OS Login PAM configuration created"
        ((CONFIGS_APPLIED++))
    fi
else
    log_info "OS Login package not installed"
fi

# Configure network for GCP
log_info "Configuring network settings for GCP..."

# Configure DHCP client for GCP
DHCP_CONF="/etc/dhcp/dhclient.conf"

if [[ -f "$DHCP_CONF" ]]; then
    if ! grep -q "prepend domain-name-servers 169.254.169.254" "$DHCP_CONF"; then
        cat >> "$DHCP_CONF" <<'EOF'

# GCP DHCP Configuration
prepend domain-name-servers 169.254.169.254;
timeout 300;
retry 60;
EOF
        log_info "✓ DHCP client configured"
        ((CONFIGS_APPLIED++))
    fi
fi

# Configure kernel parameters for GCP
log_info "Configuring kernel parameters for GCP..."

cat > /etc/sysctl.d/90-gcp.conf <<'EOF'
# GCP Kernel Configuration
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.tcp_mtu_probing = 1
EOF

sysctl --system &>/dev/null || log_warn "Failed to apply sysctl settings"

log_info "✓ Kernel parameters configured"
((CONFIGS_APPLIED++))

# Install cloud-init
log_info "Installing cloud-init..."

if ! rpm -q cloud-init &>/dev/null; then
    if zypper install -y cloud-init; then
        log_info "✓ cloud-init installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install cloud-init"
    fi
else
    log_info "cloud-init already installed"
fi

# Configure cloud-init for GCP
if rpm -q cloud-init &>/dev/null; then
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
    name: gcp-user
    lock_passwd: true
    gecos: GCP User
    groups: [wheel, adm, systemd-journal]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
EOF
    
    log_info "✓ cloud-init configured for GCP"
    ((CONFIGS_APPLIED++))
fi

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

if rpm -q google-compute-engine &>/dev/null; then
    log_info "  ✓ GCP guest environment installed"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ GCP guest environment not found"
    ((COMPONENTS_FAIL++))
fi

if command -v gcloud &>/dev/null; then
    log_info "  ✓ Google Cloud SDK available"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ Google Cloud SDK not found"
    ((COMPONENTS_FAIL++))
fi

if systemctl list-unit-files | grep -q "google-guest-agent"; then
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
log_info "Installed components:"
log_info "  - Guest environment: $(rpm -q google-compute-engine --queryformat '%{VERSION}' 2>/dev/null || echo 'not installed')"
log_info "  - Google Cloud SDK: $(gcloud version 2>/dev/null | grep "Google Cloud SDK" | awk '{print $4}' || echo 'not installed')"
log_info "  - OS Login: $(rpm -q google-compute-engine-oslogin --queryformat '%{VERSION}' 2>/dev/null || echo 'not installed')"
log_info ""
log_info "Helper commands:"
log_info "  - Get instance ID: gcp-metadata instance/id"
log_info "  - Get zone: gcp-metadata instance/zone"
log_info "  - Get project ID: gcp-metadata project/project-id"