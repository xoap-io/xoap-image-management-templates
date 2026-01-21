#!/bin/bash
#===================================================================================
# Script: install_podman.sh
# Description: Install Podman and buildah for rootless containers on RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./install_podman.sh [--user USERNAME]
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
PODMAN_USER="${PODMAN_USER:-}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            PODMAN_USER="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting Podman installation..."

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

# Install Podman and related tools
log_info "Installing Podman packages..."

PODMAN_PACKAGES="podman buildah skopeo slirp4netns fuse-overlayfs"

if $PKG_MGR install -y $PODMAN_PACKAGES; then
    log_info "✓ Podman packages installed successfully"
    ((PACKAGES_INSTALLED++))
else
    log_error "Failed to install Podman packages"
    exit 1
fi

# Get installed versions
PODMAN_VERSION=$(podman --version | awk '{print $3}')
log_info "Podman version: $PODMAN_VERSION"

BUILDAH_VERSION=$(buildah --version | awk '{print $3}')
log_info "Buildah version: $BUILDAH_VERSION"

SKOPEO_VERSION=$(skopeo --version | awk '{print $3}')
log_info "Skopeo version: $SKOPEO_VERSION"

# Configure container storage
log_info "Configuring container storage..."

STORAGE_CONF="/etc/containers/storage.conf"

if [[ -f "$STORAGE_CONF" ]]; then
    # Ensure overlay driver is configured
    if ! grep -q "^driver = \"overlay\"" "$STORAGE_CONF"; then
        sed -i 's/^driver = .*/driver = "overlay"/' "$STORAGE_CONF" 2>/dev/null || \
            echo 'driver = "overlay"' >> "$STORAGE_CONF"
        log_info "✓ Storage driver set to overlay"
    else
        log_info "Storage driver already set to overlay"
    fi
else
    log_warn "Storage configuration file not found"
fi

# Configure registries
log_info "Configuring container registries..."

REGISTRIES_CONF="/etc/containers/registries.conf"

if [[ -f "$REGISTRIES_CONF" ]]; then
    # Add Docker Hub if not present
    if ! grep -q "docker.io" "$REGISTRIES_CONF"; then
        cat >> "$REGISTRIES_CONF" <<EOF

# Docker Hub
[[registry]]
location = "docker.io"
EOF
        log_info "✓ Docker Hub registry added"
    else
        log_info "Registries already configured"
    fi
fi

# Configure user namespaces for rootless operation
if [[ -n "$PODMAN_USER" ]]; then
    log_info "Configuring rootless Podman for user: $PODMAN_USER"
    
    # Check if user exists
    if ! id "$PODMAN_USER" &>/dev/null; then
        log_error "User '$PODMAN_USER' does not exist"
        exit 1
    fi
    
    # Configure subuid and subgid
    if ! grep -q "^$PODMAN_USER:" /etc/subuid; then
        log_info "Configuring subordinate UIDs for $PODMAN_USER..."
        
        USER_UID=$(id -u "$PODMAN_USER")
        echo "$PODMAN_USER:$((USER_UID * 65536)):65536" >> /etc/subuid
        echo "$PODMAN_USER:$((USER_UID * 65536)):65536" >> /etc/subgid
        
        log_info "✓ Subordinate UIDs/GIDs configured"
    else
        log_info "Subordinate UIDs/GIDs already configured"
    fi
    
    # Create user systemd directory
    USER_HOME=$(eval echo ~"$PODMAN_USER")
    USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
    
    if [[ ! -d "$USER_SYSTEMD_DIR" ]]; then
        sudo -u "$PODMAN_USER" mkdir -p "$USER_SYSTEMD_DIR"
        log_info "✓ User systemd directory created"
    fi
    
    # Enable linger for user (allows systemd services to run without login)
    if loginctl enable-linger "$PODMAN_USER" 2>/dev/null; then
        log_info "✓ Linger enabled for $PODMAN_USER"
    else
        log_warn "Failed to enable linger for $PODMAN_USER"
    fi
fi

# Configure kernel parameters for rootless containers
log_info "Configuring kernel parameters..."

SYSCTL_CONF="/etc/sysctl.d/99-podman.conf"

if [[ ! -f "$SYSCTL_CONF" ]]; then
    cat > "$SYSCTL_CONF" <<EOF
# Podman rootless containers configuration
user.max_user_namespaces = 15000
EOF
    
    sysctl --system &>/dev/null || log_warn "Failed to reload sysctl"
    log_info "✓ Kernel parameters configured"
else
    log_info "Kernel parameters already configured"
fi

# Test Podman installation
log_info "Testing Podman installation..."

if podman info &>/tmp/podman-info.log; then
    log_info "✓ Podman installation test passed"
else
    log_error "Podman installation test failed"
    cat /tmp/podman-info.log
    exit 1
fi

# Test with hello-world container
log_info "Running test container..."

if podman run --rm docker.io/hello-world &>/tmp/podman-hello.log; then
    log_info "✓ Container test passed"
else
    log_warn "Container test failed (may be network related)"
fi

# Display Podman system information
log_info "Podman system information:"
podman info | head -n 40 | while IFS= read -r line; do
    log_info "  $line"
done

# Configure Podman socket (for Docker compatibility)
log_info "Configuring Podman socket..."

if systemctl list-unit-files | grep -q "podman.socket"; then
    systemctl enable podman.socket
    log_info "✓ Podman socket enabled"
else
    log_warn "Podman socket unit not available"
fi

# Create docker compatibility symlink
if [[ ! -L /usr/bin/docker ]] && [[ ! -f /usr/bin/docker ]]; then
    log_info "Creating Docker compatibility symlink..."
    ln -s /usr/bin/podman /usr/bin/docker
    log_info "✓ Docker symlink created (podman-docker compatibility)"
else
    log_info "Docker command already exists"
fi

# Configure Podman Compose (optional)
if command -v pip3 &>/dev/null; then
    log_info "Installing podman-compose..."
    
    if pip3 install --quiet podman-compose 2>/dev/null; then
        log_info "✓ podman-compose installed"
        COMPOSE_VERSION=$(podman-compose --version 2>/dev/null || echo "unknown")
        log_info "podman-compose version: $COMPOSE_VERSION"
    else
        log_warn "Failed to install podman-compose"
    fi
else
    log_info "pip3 not available, skipping podman-compose installation"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Podman Installation Summary"
log_info "=============================================="
log_info "Podman version: $PODMAN_VERSION"
log_info "Buildah version: $BUILDAH_VERSION"
log_info "Skopeo version: $SKOPEO_VERSION"
log_info "Rootless user: $([ -n "$PODMAN_USER" ] && echo "$PODMAN_USER" || echo 'not configured')"
log_info "Docker compatibility: $([ -L /usr/bin/docker ] && echo 'enabled' || echo 'disabled')"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Podman installation completed!"
log_info ""
log_info "Usage examples:"
log_info "  - Run container: podman run -it fedora bash"
log_info "  - List images: podman images"
log_info "  - List containers: podman ps -a"
log_info "  - Build image: buildah bud -t myimage ."
log_info "  - Copy image: skopeo copy docker://alpine:latest containers-storage:alpine:latest"
if [[ -n "$PODMAN_USER" ]]; then
    log_info ""
    log_info "Rootless usage (as $PODMAN_USER):"
    log_info "  - su - $PODMAN_USER"
    log_info "  - podman run --rm hello-world"
fi