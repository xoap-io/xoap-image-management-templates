#!/bin/bash
#===================================================================================
# Script: install_docker_ubuntu.sh
# Description: Install Docker CE for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./install_docker_ubuntu.sh [--version VERSION]
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
DOCKER_VERSION="${DOCKER_VERSION:-latest}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            DOCKER_VERSION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting Docker CE installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0

# Update package lists
apt-get update -qq

# Remove old Docker versions
log_info "Removing old Docker versions..."

OLD_PACKAGES="docker docker-engine docker.io containerd runc"

for pkg in $OLD_PACKAGES; do
    if dpkg -l | grep -q "^ii.*$pkg"; then
        log_info "  Removing $pkg..."
        apt-get remove -y "$pkg" || log_warn "Failed to remove $pkg"
    fi
done

# Install required packages
log_info "Installing required packages..."

if DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release; then
    log_info "✓ Required packages installed"
    ((PACKAGES_INSTALLED++))
else
    log_error "Failed to install required packages"
    exit 1
fi

# Add Docker GPG key
log_info "Adding Docker GPG key..."

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

log_info "✓ Docker GPG key added"

# Add Docker repository
log_info "Adding Docker repository..."

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq

log_info "✓ Docker repository added"
((PACKAGES_INSTALLED++))

# Install Docker CE
log_info "Installing Docker CE..."

if [[ "$DOCKER_VERSION" == "latest" ]]; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_info "✓ Docker CE installed successfully"
        ((PACKAGES_INSTALLED++))
    else
        log_error "Failed to install Docker CE"
        exit 1
    fi
else
    if DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce="$DOCKER_VERSION" docker-ce-cli="$DOCKER_VERSION" \
                           containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_info "✓ Docker CE $DOCKER_VERSION installed successfully"
        ((PACKAGES_INSTALLED++))
    else
        log_error "Failed to install Docker CE $DOCKER_VERSION"
        exit 1
    fi
fi

# Get installed Docker version
DOCKER_VERSION_INSTALLED=$(docker --version | awk '{print $3}' | tr -d ',')
log_info "Docker version: $DOCKER_VERSION_INSTALLED"

# Configure Docker daemon
log_info "Configuring Docker daemon..."

DAEMON_CONFIG="/etc/docker/daemon.json"

mkdir -p /etc/docker

cat > "$DAEMON_CONFIG" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

log_info "✓ Docker daemon configured"
((PACKAGES_INSTALLED++))

# Enable and start Docker service
log_info "Enabling Docker service..."

systemctl enable docker
systemctl start docker

# Wait for Docker to start
sleep 3

if systemctl is-active --quiet docker; then
    log_info "✓ Docker service is running"
else
    log_error "Docker service failed to start"
    systemctl status docker --no-pager
    exit 1
fi

# Test Docker installation
log_info "Testing Docker installation..."

if docker run --rm hello-world &>/tmp/docker-hello-world.log; then
    log_info "✓ Docker installation test passed"
else
    log_error "Docker installation test failed"
    cat /tmp/docker-hello-world.log
    exit 1
fi

# Display Docker information
log_info "Docker system information:"
docker info 2>/dev/null | head -n 30 | while IFS= read -r line; do
    log_info "  $line"
done

# Display Docker Compose version
if command -v docker &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version 2>/dev/null | awk '{print $NF}' || echo "not available")
    log_info "Docker Compose version: $COMPOSE_VERSION"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Docker CE Installation Summary"
log_info "=============================================="
log_info "Docker version: $DOCKER_VERSION_INSTALLED"
log_info "Docker Compose: $(command -v docker compose &>/dev/null && echo 'installed' || echo 'not installed')"
log_info "Service status: $(systemctl is-active docker)"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Docker CE installation completed!"
log_info ""
log_info "Next steps:"
log_info "  - Test: docker run hello-world"
log_info "  - Compose: docker compose --version"
log_info "  - Info: docker info"