#!/bin/bash
#===================================================================================
# Script: install_podman_ubuntu.sh
# Description: Install Podman and buildah for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./install_podman_ubuntu.sh
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

log_info "Starting Podman installation for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
PACKAGES_INSTALLED=0

# Update package lists
apt-get update -qq

# Add Podman repository (for Ubuntu < 22.04 or for latest version)
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)

log_info "Ubuntu version: $UBUNTU_VERSION ($UBUNTU_CODENAME)"

# For Ubuntu 20.04, add Podman PPA
if [[ "$UBUNTU_VERSION" == "20.04" ]]; then
    log_info "Adding Podman PPA for Ubuntu 20.04..."
    
    if ! dpkg -l | grep -q "^ii.*software-properties-common"; then
        apt-get install -y software-properties-common
    fi
    
    add-apt-repository -y ppa:projectatomic/ppa
    apt-get update -qq
    
    log_info "✓ Podman PPA added"
fi

# Install Podman and related tools
log_info "Installing Podman packages..."

PODMAN_PACKAGES="podman buildah skopeo"

if DEBIAN_FRONTEND=noninteractive apt-get install -y $PODMAN_PACKAGES; then
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
    if ! grep -q "^driver = \"overlay\"" "$STORAGE_CONF"; then
        sed -i 's/^driver = .*/driver = "overlay"/' "$STORAGE_CONF" 2>/dev/null || \
            echo 'driver = "overlay"' >> "$STORAGE_CONF"
        log_info "✓ Storage driver set to overlay"
        ((PACKAGES_INSTALLED++))
    else
        log_info "Storage driver already set to overlay"
    fi
fi

# Configure registries
log_info "Configuring container registries..."

REGISTRIES_CONF="/etc/containers/registries.conf"

if [[ -f "$REGISTRIES_CONF" ]]; then
    cp "$REGISTRIES_CONF" "${REGISTRIES_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
    
    if ! grep -q "docker.io" "$REGISTRIES_CONF"; then
        cat >> "$REGISTRIES_CONF" <<'EOF'

# Docker Hub
unqualified-search-registries = ["docker.io"]

[[registry]]
location = "docker.io"
EOF
        log_info "✓ Docker Hub registry added"
        ((PACKAGES_INSTALLED++))
    else
        log_info "Registries already configured"
    fi
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

# Run test container
log_info "Running test container..."

if podman run --rm docker.io/hello-world &>/tmp/podman-hello.log; then
    log_info "✓ Container test passed"
else
    log_warn "Container test failed (may be network related)"
fi

# Display Podman system information
log_info "Podman system information:"
podman info 2>/dev/null | head -n 40 | while IFS= read -r line; do
    log_info "  $line"
done

# Configure Podman socket (for Docker compatibility)
log_info "Configuring Podman socket..."

if systemctl list-unit-files | grep -q "podman.socket"; then
    systemctl enable podman.socket
    log_info "✓ Podman socket enabled"
    ((PACKAGES_INSTALLED++))
else
    log_warn "Podman socket unit not available"
fi

# Create docker compatibility alias (optional)
if [[ ! -L /usr/bin/docker ]] && [[ ! -f /usr/bin/docker ]]; then
    log_info "Creating Docker compatibility symlink..."
    ln -s /usr/bin/podman /usr/bin/docker
    log_info "✓ Docker symlink created (podman-docker compatibility)"
else
    log_info "Docker command already exists"
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
log_info "Docker compatibility: $([ -L /usr/bin/docker ] && echo 'enabled' || echo 'disabled')"
log_info "Packages installed: $PACKAGES_INSTALLED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Podman installation completed!"
log_info ""
log_info "Usage examples:"
log_info "  - Run container: podman run -it ubuntu bash"
log_info "  - List images: podman images"
log_info "  - List containers: podman ps -a"
log_info "  - Build image: buildah bud -t myimage ."