#!/bin/bash
#===================================================================================
# Script: prepare_kubernetes_node_suse.sh
# Description: Prepare SUSE/openSUSE system as Kubernetes node
# Author: XOAP Infrastructure Team
# Usage: ./prepare_kubernetes_node_suse.sh [--container-runtime containerd]
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
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-containerd}"
K8S_VERSION="${K8S_VERSION:-1.28}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --container-runtime)
            CONTAINER_RUNTIME="$2"
            shift 2
            ;;
        --k8s-version)
            K8S_VERSION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting Kubernetes node preparation for SUSE..."
log_info "Container runtime: $CONTAINER_RUNTIME"
log_info "Kubernetes version: $K8S_VERSION"

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Disable swap
log_info "Disabling swap..."

if [[ $(swapon --show | wc -l) -gt 0 ]]; then
    swapoff -a
    log_info "✓ Swap disabled"
    ((CONFIGS_APPLIED++))
    
    # Comment out swap in fstab
    sed -i '/swap/s/^/#/' /etc/fstab
    log_info "✓ Swap entries commented in fstab"
else
    log_info "Swap is already disabled"
fi

# Load required kernel modules
log_info "Loading required kernel modules..."

MODULES_CONF="/etc/modules-load.d/kubernetes.conf"

cat > "$MODULES_CONF" <<'EOF'
# Kubernetes required modules
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

log_info "✓ Kernel modules loaded"
((CONFIGS_APPLIED++))

# Configure sysctl parameters
log_info "Configuring kernel parameters..."

SYSCTL_CONF="/etc/sysctl.d/kubernetes.conf"

cat > "$SYSCTL_CONF" <<'EOF'
# Kubernetes required kernel parameters
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system &>/dev/null || log_warn "Failed to reload sysctl"

log_info "✓ Kernel parameters configured"
((CONFIGS_APPLIED++))

# Verify kernel parameters
log_info "Verifying kernel parameters:"
log_info "  bridge-nf-call-iptables: $(cat /proc/sys/net/bridge/bridge-nf-call-iptables)"
log_info "  bridge-nf-call-ip6tables: $(cat /proc/sys/net/bridge/bridge-nf-call-ip6tables)"
log_info "  ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"

# Disable firewall
log_info "Disabling firewall..."

if systemctl is-active --quiet firewalld; then
    systemctl stop firewalld
    systemctl disable firewalld
    log_info "✓ firewalld disabled"
    ((CONFIGS_APPLIED++))
else
    log_info "firewalld already disabled"
fi

# Install container runtime
log_info "Installing container runtime: $CONTAINER_RUNTIME"

if [[ "$CONTAINER_RUNTIME" == "containerd" ]]; then
    log_info "Installing containerd..."
    
    if zypper install -y containerd; then
        log_info "✓ containerd installed"
        
        # Configure containerd
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        
        # Enable SystemdCgroup
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        
        systemctl enable containerd
        systemctl start containerd
        
        if systemctl is-active --quiet containerd; then
            log_info "✓ containerd is running"
            ((CONFIGS_APPLIED++))
        else
            log_error "Failed to start containerd"
            exit 1
        fi
    else
        log_error "Failed to install containerd"
        exit 1
    fi
else
    log_error "Unsupported container runtime: $CONTAINER_RUNTIME"
    exit 1
fi

# Add Kubernetes repository
log_info "Adding Kubernetes repository..."

cat > /etc/zypp/repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
EOF

log_info "✓ Kubernetes repository added"
((CONFIGS_APPLIED++))

# Refresh repositories
zypper refresh

# Install Kubernetes packages
log_info "Installing Kubernetes packages..."

if zypper install -y kubelet kubeadm kubectl; then
    log_info "✓ Kubernetes packages installed"
    ((CONFIGS_APPLIED++))
else
    log_error "Failed to install Kubernetes packages"
    exit 1
fi

# Enable kubelet
systemctl enable kubelet

log_info "✓ kubelet enabled"

# Display installed versions
log_info "Installed Kubernetes versions:"
log_info "  kubelet: $(kubelet --version | awk '{print $2}')"
log_info "  kubeadm: $(kubeadm version -o short)"
log_info "  kubectl: $(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4 || echo 'unknown')"

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Kubernetes Node Preparation Summary"
log_info "=============================================="
log_info "Container runtime: $CONTAINER_RUNTIME"
log_info "Runtime status: $(systemctl is-active $CONTAINER_RUNTIME)"
log_info "Kubernetes version: $(kubelet --version | awk '{print $2}')"
log_info "Swap status: $([ $(swapon --show | wc -l) -eq 0 ] && echo 'disabled' || echo 'enabled')"
log_info "Configurations applied: $CONFIGS_APPLIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Kubernetes node preparation completed!"
log_info ""
log_info "Next steps:"
log_info "  Control plane: kubeadm init --pod-network-cidr=10.244.0.0/16"
log_info "  Worker node: kubeadm join <control-plane-endpoint> --token <token>"