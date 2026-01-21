#!/bin/bash
#===================================================================================
# Script: install_docker.sh
# Description: Install Docker CE on RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./install_docker.sh [--version VERSION] [--rootless]
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
ROOTLESS_MODE="${ROOTLESS_MODE:-false}"
DOCKER_USER="${DOCKER_USER:-}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            DOCKER_VERSION="$2"
            shift 2
            ;;
        --rootless)
            ROOTLESS_MODE="true"
            shift
            ;;
        --user)
            DOCKER_USER="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting Docker CE installation..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

# Remove old Docker versions if present
log_info "Removing old Docker versions..."

OLD_PACKAGES="docker docker-client docker-client-latest docker-common docker-latest \
              docker-latest-logrotate docker-logrotate docker-engine podman runc"

for pkg in $OLD_PACKAGES; do
    if rpm -q "$pkg" &>/dev/null; then
        log_info "Removing $pkg..."
        $PKG_MGR remove -y "$pkg" || log_warn "Failed to remove $pkg"
    fi
done

# Install required packages
log_info "Installing required packages..."

REQUIRED_PACKAGES="yum-utils device-mapper-persistent-data lvm2"

if $PKG_MGR install -y $REQUIRED_PACKAGES; then
    log_info "✓ Required packages installed"
    ((PACKAGES_INSTALLED++))
else
    log_error "Failed to install required packages"
    exit 1
fi

# Add Docker repository
log_info "Adding Docker CE repository..."

REPO_FILE="/etc/yum.repos.d/docker-ce.repo"

if [[ ! -f "$REPO_FILE" ]]; then
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    log_info "✓ Docker repository added"
else
    log_info "Docker repository already configured"
fi

# Install Docker CE
log_info "Installing Docker CE..."

if [[ "$DOCKER_VERSION" == "latest" ]]; then
    log_info "Installing latest Docker CE version..."
    
    if $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_info "✓ Docker CE installed successfully"
        ((PACKAGES_INSTALLED++))
    else
        log_error "Failed to install Docker CE"
        exit 1
    fi
else
    log_info "Installing Docker CE version: $DOCKER_VERSION..."
    
    if $PKG_MGR install -y "docker-ce-${DOCKER_VERSION}" "docker-ce-cli-${DOCKER_VERSION}" \
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

if [[ ! -f "$DAEMON_CONFIG" ]]; then
    mkdir -p /etc/docker
    
    cat > "$DAEMON_CONFIG" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
    
    log_info "✓ Docker daemon configured"
else
    log_info "Docker daemon configuration already exists"
fi

# Enable and start Docker service
log_info "Enabling Docker service..."

systemctl enable docker
systemctl start docker

# Verify Docker service status
sleep 2

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

# Configure rootless mode if requested
if [[ "$ROOTLESS_MODE" == "true" ]]; then
    log_info "Configuring rootless Docker..."
    
    if [[ -z "$DOCKER_USER" ]]; then
        log_error "Rootless mode requested but no user specified (use --user)"
        exit 1
    fi
    
    # Install rootless extras
    if $PKG_MGR install -y docker-ce-rootless-extras; then
        log_info "✓ Rootless extras installed"
        ((PACKAGES_INSTALLED++))
    else
        log_error "Failed to install rootless extras"
        exit 1
    fi
    
    # Configure user namespaces
    if ! grep -q "^$DOCKER_USER:" /etc/subuid; then
        log_info "Configuring user namespaces for $DOCKER_USER..."
        
        USER_UID=$(id -u "$DOCKER_USER")
        echo "$DOCKER_USER:$((USER_UID * 65536)):65536" >> /etc/subuid
        echo "$DOCKER_USER:$((USER_UID * 65536)):65536" >> /etc/subgid
        
        log_info "✓ User namespaces configured"
    fi
    
    log_info "To setup rootless Docker for $DOCKER_USER, run as that user:"
    log_info "  dockerd-rootless-setuptool.sh install"
else
    # Add user to docker group (if user specified)
    if [[ -n "$DOCKER_USER" ]]; then
        log_info "Adding user '$DOCKER_USER' to docker group..."
        
        if usermod -aG docker "$DOCKER_USER"; then
            log_info "✓ User added to docker group"
            log_info "User must log out and back in for changes to take effect"
        else
            log_warn "Failed to add user to docker group"
        fi
    fi
fi

# Display Docker information
log_info "Docker system information:"
docker info | head -n 30 | while IFS= read -r line; do
    log_info "  $line"
done

# Display Docker Compose version
if command -v docker compose &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version | awk '{print $NF}')
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
log_info "Rootless mode: $([ "$ROOTLESS_MODE" == "true" ] && echo 'configured' || echo 'disabled')"
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