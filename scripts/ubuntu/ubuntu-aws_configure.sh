#!/bin/bash
#===================================================================================
# Script: aws_configure_ubuntu.sh
# Description: Configure Ubuntu for AWS EC2
# Author: XOAP Infrastructure Team
# Usage: ./aws_configure_ubuntu.sh
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

log_info "Starting AWS configuration for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Detect if running on AWS
log_info "Detecting cloud platform..."

if [[ -f /sys/hypervisor/uuid ]] && grep -qi "ec2" /sys/hypervisor/uuid 2>/dev/null; then
    log_info "Running on AWS EC2"
elif curl -s -m 2 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
    log_info "AWS metadata service detected"
else
    log_warn "Not running on AWS - some features may not work"
fi

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Install cloud-init
log_info "Installing cloud-init..."

if ! dpkg -l | grep -q "^ii.*cloud-init"; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-init; then
        log_info "✓ cloud-init installed"
        ((CONFIGS_APPLIED++))
    else
        log_error "Failed to install cloud-init"
        exit 1
    fi
else
    log_info "cloud-init already installed"
fi

# Configure cloud-init for AWS
log_info "Configuring cloud-init for AWS..."

CLOUD_CFG="/etc/cloud/cloud.cfg.d/90-aws.cfg"

cat > "$CLOUD_CFG" <<'EOF'
# AWS EC2 Configuration
datasource_list: [ Ec2, None ]
datasource:
  Ec2:
    timeout: 50
    max_wait: 120
    metadata_urls: [ 'http://169.254.169.254' ]
    strict_id: false

# Disable network configuration by cloud-init
network:
  config: disabled

# System info
system_info:
  default_user:
    name: ubuntu
    lock_passwd: true
    gecos: Ubuntu
    groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
EOF

log_info "✓ cloud-init configured for AWS"
((CONFIGS_APPLIED++))

# Clean cloud-init for image preparation
cloud-init clean --logs --seed

# Install AWS CLI
log_info "Installing AWS CLI..."

if ! command -v aws &>/dev/null; then
    cd /tmp
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install --update
    rm -rf aws awscliv2.zip
    
    if command -v aws &>/dev/null; then
        AWS_VERSION=$(aws --version)
        log_info "✓ AWS CLI installed: $AWS_VERSION"
        ((CONFIGS_APPLIED++))
    else
        log_warn "AWS CLI installation may have failed"
    fi
else
    AWS_VERSION=$(aws --version)
    log_info "AWS CLI already installed: $AWS_VERSION"
fi

# Install SSM Agent
log_info "Installing AWS SSM Agent..."

if ! systemctl list-unit-files | grep -q "snap.amazon-ssm-agent"; then
    if snap install amazon-ssm-agent --classic; then
        log_info "✓ SSM Agent installed via snap"
        ((CONFIGS_APPLIED++))
    else
        # Fallback to manual installation
        cd /tmp
        wget -q https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
        
        if dpkg -i amazon-ssm-agent.deb; then
            log_info "✓ SSM Agent installed"
            ((CONFIGS_APPLIED++))
        else
            log_warn "Failed to install SSM Agent"
        fi
        rm -f amazon-ssm-agent.deb
    fi
else
    log_info "SSM Agent already installed"
fi

# Enable and start SSM Agent
if systemctl list-unit-files | grep -q "amazon-ssm-agent\|snap.amazon-ssm-agent"; then
    systemctl enable amazon-ssm-agent 2>/dev/null || systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || true
    systemctl start amazon-ssm-agent 2>/dev/null || systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || true
    
    if systemctl is-active --quiet amazon-ssm-agent 2>/dev/null || systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null; then
        log_info "✓ SSM Agent is running"
    else
        log_info "SSM Agent service enabled (will start on AWS)"
    fi
fi

# Install CloudWatch Agent
log_info "Installing Amazon CloudWatch Agent..."

if ! dpkg -l | grep -q "amazon-cloudwatch-agent"; then
    cd /tmp
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    
    if dpkg -i amazon-cloudwatch-agent.deb; then
        log_info "✓ CloudWatch Agent installed"
        ((CONFIGS_APPLIED++))
    else
        log_warn "Failed to install CloudWatch Agent"
    fi
    rm -f amazon-cloudwatch-agent.deb
else
    log_info "CloudWatch Agent already installed"
fi

# Configure network for AWS
log_info "Configuring network settings for AWS..."

cat > /etc/sysctl.d/90-aws.conf <<'EOF'
# AWS Network Configuration
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
EOF

sysctl --system &>/dev/null || log_warn "Failed to apply sysctl settings"

log_info "✓ Network settings configured"
((CONFIGS_APPLIED++))

# Configure IMDSv2
log_info "Configuring for IMDSv2..."

cat > /etc/profile.d/aws-imds.sh <<'EOF'
# AWS IMDSv2 Configuration
export AWS_METADATA_SERVICE_TIMEOUT=5
export AWS_METADATA_SERVICE_NUM_ATTEMPTS=3
EOF

chmod +x /etc/profile.d/aws-imds.sh

log_info "✓ IMDSv2 configuration added"
((CONFIGS_APPLIED++))

# Install NVMe tools for EBS
log_info "Installing NVMe tools for EBS volumes..."

if DEBIAN_FRONTEND=noninteractive apt-get install -y nvme-cli; then
    log_info "✓ NVMe CLI installed"
    ((CONFIGS_APPLIED++))
else
    log_warn "Failed to install NVMe CLI"
fi

# Configure ENA driver
log_info "Configuring ENA driver..."

if ! lsmod | grep -q "^ena"; then
    if modprobe ena 2>/dev/null; then
        log_info "✓ ENA driver loaded"
        echo "ena" >> /etc/modules
        ((CONFIGS_APPLIED++))
    else
        log_info "ENA driver will be loaded when running on AWS"
    fi
else
    log_info "ENA driver already loaded"
fi

# Create helper script for AWS metadata
log_info "Creating AWS metadata helper script..."

cat > /usr/local/bin/aws-metadata <<'EOF'
#!/bin/bash
# AWS EC2 Metadata Helper Script

IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)

if [[ -n "$IMDS_TOKEN" ]]; then
    curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" "http://169.254.169.254/latest/meta-data/${1}"
else
    curl -s "http://169.254.169.254/latest/meta-data/${1}"
fi
EOF

chmod +x /usr/local/bin/aws-metadata

log_info "✓ AWS metadata helper created"
((CONFIGS_APPLIED++))

# Verify installations
log_info "Verifying AWS components..."

COMPONENTS_OK=0
COMPONENTS_FAIL=0

if dpkg -l | grep -q "^ii.*cloud-init"; then
    log_info "  ✓ cloud-init installed"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ cloud-init not found"
    ((COMPONENTS_FAIL++))
fi

if command -v aws &>/dev/null; then
    log_info "  ✓ AWS CLI available"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ AWS CLI not found"
    ((COMPONENTS_FAIL++))
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "AWS Configuration Summary"
log_info "=============================================="
log_info "Configurations applied: $CONFIGS_APPLIED"
log_info "Components OK: $COMPONENTS_OK"
log_info "Components failed: $COMPONENTS_FAIL"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "AWS configuration completed!"
log_info ""
log_info "Installed components:"
log_info "  - cloud-init: $(dpkg -l cloud-init 2>/dev/null | grep '^ii' | awk '{print $3}' || echo 'not installed')"
log_info "  - AWS CLI: $(aws --version 2>/dev/null || echo 'not installed')"
log_info ""
log_info "Helper commands:"
log_info "  - Get instance ID: aws-metadata instance-id"
log_info "  - Get region: aws-metadata placement/region"
log_info "  - Get public IP: aws-metadata public-ipv4"