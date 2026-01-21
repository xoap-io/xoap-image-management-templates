#!/bin/bash
#===================================================================================
# Script: aws_configure.sh
# Description: Configure AWS-specific settings for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./aws_configure.sh
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

log_info "Starting AWS configuration..."

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
# Task 1: Install cloud-init
#===================================================================================
log_info "[Task 1/4] Installing cloud-init..."

if rpm -q cloud-init &>/dev/null; then
    log_info "cloud-init is already installed"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    if $PKG_MGR install -y cloud-init 2>&1 | tee -a /tmp/aws-config.log; then
        log_info "cloud-init installed successfully"
        TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    else
        log_warn "Failed to install cloud-init"
        TASKS_FAILED=$((TASKS_FAILED + 1))
    fi
fi

# Configure cloud-init for AWS
if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    log_info "Configuring cloud-init datasource..."
    
    cat <<'EOF' > /etc/cloud/cloud.cfg.d/90_aws.cfg
# AWS-specific cloud-init configuration
datasource_list: [ Ec2 ]
datasource:
  Ec2:
    timeout: 5
    max_wait: 10
    metadata_urls: [ 'http://169.254.169.254' ]
EOF
    
    log_info "cloud-init configured for AWS"
fi

#===================================================================================
# Task 2: Install AWS CLI
#===================================================================================
log_info "[Task 2/4] Installing AWS CLI..."

if command -v aws &>/dev/null; then
    log_info "AWS CLI is already installed"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    
    if command -v aws &>/dev/null; then
        log_info "AWS CLI installed successfully"
        log_info "AWS CLI version: $(aws --version)"
        TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    else
        log_warn "Failed to install AWS CLI"
        TASKS_FAILED=$((TASKS_FAILED + 1))
    fi
    
    # Cleanup
    rm -rf /tmp/aws /tmp/awscliv2.zip
fi

#===================================================================================
# Task 3: Install SSM Agent
#===================================================================================
log_info "[Task 3/4] Installing AWS Systems Manager Agent..."

if rpm -q amazon-ssm-agent &>/dev/null; then
    log_info "SSM Agent is already installed"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
else
    # Detect architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        SSM_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
    elif [[ "$ARCH" == "aarch64" ]]; then
        SSM_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_arm64/amazon-ssm-agent.rpm"
    else
        log_error "Unsupported architecture: $ARCH"
        TASKS_FAILED=$((TASKS_FAILED + 1))
        SSM_URL=""
    fi
    
    if [[ -n "$SSM_URL" ]]; then
        if $PKG_MGR install -y "$SSM_URL" 2>&1 | tee -a /tmp/aws-config.log; then
            systemctl enable amazon-ssm-agent
            systemctl start amazon-ssm-agent
            
            log_info "SSM Agent installed and started"
            TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
        else
            log_warn "Failed to install SSM Agent"
            TASKS_FAILED=$((TASKS_FAILED + 1))
        fi
    fi
fi

#===================================================================================
# Task 4: Configure IMDSv2
#===================================================================================
log_info "[Task 4/4] Configuring Instance Metadata Service v2..."

# Create script to configure IMDSv2 on first boot
cat <<'EOF' > /usr/local/bin/configure-imdsv2.sh
#!/bin/bash
# Configure applications to use IMDSv2

# Set AWS CLI to use IMDSv2
export AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv4
export AWS_EC2_METADATA_SERVICE_ENDPOINT=http://169.254.169.254

# Add to profile
if ! grep -q "AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE" /etc/profile.d/aws-imdsv2.sh 2>/dev/null; then
    cat <<'PROFILE' > /etc/profile.d/aws-imdsv2.sh
export AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv4
export AWS_EC2_METADATA_SERVICE_ENDPOINT=http://169.254.169.254
PROFILE
fi
EOF

chmod +x /usr/local/bin/configure-imdsv2.sh
/usr/local/bin/configure-imdsv2.sh

log_info "IMDSv2 configuration completed"
TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "AWS Configuration Summary"
log_info "=============================================="
log_info "Tasks completed: $TASKS_COMPLETED/4"
log_info "Tasks failed: $TASKS_FAILED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "AWS configuration completed!"