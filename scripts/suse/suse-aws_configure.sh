#!/bin/bash
#===================================================================================
# Script: aws_configure_suse.sh
# Description: Configure SUSE/openSUSE for AWS EC2
# Author: XOAP Infrastructure Team
# Usage: ./aws_configure_suse.sh
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

log_info "Starting AWS configuration for SUSE..."

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

# Install cloud-init
log_info "Installing cloud-init..."

if ! rpm -q cloud-init &>/dev/null; then
    if zypper install -y cloud-init; then
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

CLOUD_CFG="/etc/cloud/cloud.cfg"

if [[ -f "$CLOUD_CFG" ]]; then
    # Backup original config
    cp "$CLOUD_CFG" "${CLOUD_CFG}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Ensure AWS datasource is enabled
    if ! grep -q "datasource_list.*Ec2" "$CLOUD_CFG"; then
        cat >> "$CLOUD_CFG" <<'EOF'

# AWS EC2 Configuration
datasource_list: [ Ec2, None ]
datasource:
  Ec2:
    timeout: 50
    max_wait: 120
    metadata_urls: [ 'http://169.254.169.254' ]
EOF
        log_info "✓ AWS datasource configured"
        ((CONFIGS_APPLIED++))
    fi
fi

# Enable cloud-init services
log_info "Enabling cloud-init services..."

for service in cloud-init-local cloud-init cloud-config cloud-final; do
    if systemctl enable "${service}.service" 2>/dev/null; then
        log_info "  ✓ Enabled ${service}.service"
    else
        log_warn "  ✗ Failed to enable ${service}.service"
    fi
done

((CONFIGS_APPLIED++))

# Install AWS CLI
log_info "Installing AWS CLI..."

if ! command -v aws &>/dev/null; then
    # Install AWS CLI v2
    if zypper install -y unzip curl; then
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
        log_warn "Failed to install AWS CLI dependencies"
    fi
else
    AWS_VERSION=$(aws --version)
    log_info "AWS CLI already installed: $AWS_VERSION"
fi

# Install SSM Agent
log_info "Installing AWS SSM Agent..."

if ! rpm -q amazon-ssm-agent &>/dev/null; then
    # Download and install SSM Agent
    SSM_REGION="us-east-1"
    SSM_URL="https://s3.${SSM_REGION}.amazonaws.com/amazon-ssm-${SSM_REGION}/latest/linux_amd64/amazon-ssm-agent.rpm"
    
    cd /tmp
    if curl -s -o amazon-ssm-agent.rpm "$SSM_URL"; then
        if zypper install -y ./amazon-ssm-agent.rpm; then
            log_info "✓ SSM Agent installed"
            ((CONFIGS_APPLIED++))
        else
            log_warn "Failed to install SSM Agent"
        fi
        rm -f amazon-ssm-agent.rpm
    else
        log_warn "Failed to download SSM Agent"
    fi
else
    log_info "SSM Agent already installed"
fi

# Enable and start SSM Agent
if rpm -q amazon-ssm-agent &>/dev/null; then
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent &>/dev/null || log_warn "SSM Agent failed to start (normal if not on AWS)"
    
    if systemctl is-active --quiet amazon-ssm-agent; then
        log_info "✓ SSM Agent is running"
    else
        log_info "SSM Agent service enabled (will start on AWS)"
    fi
fi

# Install CloudWatch Agent
log_info "Installing Amazon CloudWatch Agent..."

if ! rpm -q amazon-cloudwatch-agent &>/dev/null; then
    cd /tmp
    CW_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/suse/amd64/latest/amazon-cloudwatch-agent.rpm"
    
    if curl -s -o amazon-cloudwatch-agent.rpm "$CW_URL"; then
        if zypper install -y ./amazon-cloudwatch-agent.rpm; then
            log_info "✓ CloudWatch Agent installed"
            ((CONFIGS_APPLIED++))
        else
            log_warn "Failed to install CloudWatch Agent"
        fi
        rm -f amazon-cloudwatch-agent.rpm
    else
        log_warn "Failed to download CloudWatch Agent"
    fi
else
    log_info "CloudWatch Agent already installed"
fi

# Configure network for AWS
log_info "Configuring network settings for AWS..."

# Enable source/destination check bypass (for NAT instances)
cat > /etc/sysctl.d/90-aws.conf <<'EOF'
# AWS Network Configuration
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

sysctl --system &>/dev/null || log_warn "Failed to apply sysctl settings"

log_info "✓ Network settings configured"
((CONFIGS_APPLIED++))

# Configure DHCP for AWS
log_info "Configuring DHCP client for AWS..."

DHCP_CONF="/etc/dhcp/dhclient.conf"

if [[ -f "$DHCP_CONF" ]]; then
    if ! grep -q "supersede domain-name-servers" "$DHCP_CONF"; then
        cat >> "$DHCP_CONF" <<'EOF'

# AWS DHCP Configuration
supersede domain-name-servers 169.254.169.253;
EOF
        log_info "✓ DHCP client configured"
        ((CONFIGS_APPLIED++))
    fi
fi

# Configure IMDSv2 (Instance Metadata Service v2)
log_info "Configuring for IMDSv2..."

cat > /etc/profile.d/aws-imds.sh <<'EOF'
# AWS IMDSv2 Configuration
export AWS_METADATA_SERVICE_TIMEOUT=5
export AWS_METADATA_SERVICE_NUM_ATTEMPTS=3
EOF

chmod +x /etc/profile.d/aws-imds.sh

log_info "✓ IMDSv2 configuration added"
((CONFIGS_APPLIED++))

# Install and configure NVMe tools for EBS
log_info "Installing NVMe tools for EBS volumes..."

if zypper install -y nvme-cli; then
    log_info "✓ NVMe CLI installed"
    ((CONFIGS_APPLIED++))
else
    log_warn "Failed to install NVMe CLI"
fi

# Configure automatic ENA driver loading
log_info "Configuring ENA driver..."

if ! lsmod | grep -q "^ena"; then
    if modprobe ena 2>/dev/null; then
        log_info "✓ ENA driver loaded"
        echo "ena" >> /etc/modules-load.d/aws.conf
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
    # Use IMDSv2
    curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" "http://169.254.169.254/latest/meta-data/${1}"
else
    # Fallback to IMDSv1
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

if rpm -q cloud-init &>/dev/null; then
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

if rpm -q amazon-ssm-agent &>/dev/null; then
    log_info "  ✓ SSM Agent installed"
    ((COMPONENTS_OK++))
else
    log_warn "  ✗ SSM Agent not found"
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
log_info "  - cloud-init: $(rpm -q cloud-init --queryformat '%{VERSION}' 2>/dev/null || echo 'not installed')"
log_info "  - AWS CLI: $(aws --version 2>/dev/null | awk '{print $1}' || echo 'not installed')"
log_info "  - SSM Agent: $(rpm -q amazon-ssm-agent --queryformat '%{VERSION}' 2>/dev/null || echo 'not installed')"
log_info ""
log_info "Helper commands:"
log_info "  - Get instance ID: aws-metadata instance-id"
log_info "  - Get region: aws-metadata placement/region"
log_info "  - Get public IP: aws-metadata public-ipv4"