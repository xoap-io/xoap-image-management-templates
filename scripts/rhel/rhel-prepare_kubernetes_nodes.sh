#!/bin/bash
#===================================================================================
# Script: prepare_kubernetes_node.sh
# Description: Prepare RHEL system as Kubernetes node
# Author: XOAP Infrastructure Team
# Usage: ./prepare_kubernetes_node.sh [--container-runtime docker|containerd|crio]
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

log_info "Starting Kubernetes node preparation..."
log_info "Container runtime: $CONTAINER_RUNTIME"
log_info "Kubernetes version: $K8S_VERSION"

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

# Disable swap (required for Kubernetes)
log_info "Disabling swap..."

if [[ $(swapon --show | wc -l) -gt 0 ]]; then
    swapoff -a
    log_info "✓ Swap disabled"
    ((CONFIGS_APPLIED++))
    
    # Comment out swap entries in fstab
    sed -i '/swap/s/^/#/' /etc/fstab
    log_info "✓ Swap entries commented in fstab"
else
    log_info "Swap is already disabled"
fi

# Disable SELinux (or set to permissive)
log_info "Configuring SELinux..."

CURRENT_SELINUX=$(getenforce 2>/dev/null || echo "Disabled")
log_info "Current SELinux mode: $CURRENT_SELINUX"

if [[ "$CURRENT_SELINUX" != "Permissive" ]] && [[ "$CURRENT_SELINUX" != "Disabled" ]]; then
    setenforce 0
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    log_info "✓ SELinux set to permissive"
    ((CONFIGS_APPLIED++))
else
    log_info "SELinux already in permissive or disabled mode"
fi

# Load required kernel modules
log_info "Loading required kernel modules..."

MODULES_CONF="/etc/modules-load.d/kubernetes.conf"

cat > "$MODULES_CONF" <<EOF
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

cat > "$SYSCTL_CONF" <<EOF
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

# Disable firewalld (or configure for Kubernetes)
log_info "Configuring firewall..."

if systemctl is-active --quiet firewalld; then
    log_info "Disabling firewalld (can be re-enabled with proper K8s rules)..."
    systemctl stop firewalld
    systemctl disable firewalld
    log_info "✓ Firewalld disabled"
    ((CONFIGS_APPLIED++))
else
    log_info "Firewalld is already disabled"
fi

# Install container runtime
log_info "Installing container runtime: $CONTAINER_RUNTIME"

case "$CONTAINER_RUNTIME" in
    docker)
        log_info "Installing Docker CE..."
        
        # Add Docker repository
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        
        # Install Docker
        $PKG_MGR install -y docker-ce docker-ce-cli containerd.io
        
        # Configure Docker daemon
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
        
        systemctl enable --now docker
        log_info "✓ Docker installed and started"
        ((CONFIGS_APPLIED++))
        ;;
        
    containerd)
        log_info "Installing containerd..."
        
        # Install containerd
        $PKG_MGR install -y containerd.io || $PKG_MGR install -y containerd
        
        # Configure containerd
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        
        # Enable SystemdCgroup
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        
        systemctl enable --now containerd
        log_info "✓ containerd installed and started"
        ((CONFIGS_APPLIED++))
        ;;
        
    crio)
        log_info "Installing CRI-O..."
        
        # Add CRI-O repository
        VERSION="${K8S_VERSION}"
        
        cat > /etc/yum.repos.d/cri-o.repo <<EOF
[cri-o]
name=CRI-O
baseurl=https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${VERSION}/CentOS_8/
enabled=1
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${VERSION}/CentOS_8/repodata/repomd.xml.key
EOF
        
        # Install CRI-O
        $PKG_MGR install -y cri-o
        
        systemctl enable --now crio
        log_info "✓ CRI-O installed and started"
        ((CONFIGS_APPLIED++))
        ;;
        
    *)
        log_error "Unknown container runtime: $CONTAINER_RUNTIME"
        exit 1
        ;;
esac

# Verify container runtime
sleep 2

case "$CONTAINER_RUNTIME" in
    docker)
        if systemctl is-active --quiet docker; then
            log_info "✓ Docker is running"
            docker --version | while IFS= read -r line; do
                log_info "  $line"
            done
        else
            log_error "Docker failed to start"
            exit 1
        fi
        ;;
    containerd)
        if systemctl is-active --quiet containerd; then
            log_info "✓ containerd is running"
            containerd --version | while IFS= read -r line; do
                log_info "  $line"
            done
        else
            log_error "containerd failed to start"
            exit 1
        fi
        ;;
    crio)
        if systemctl is-active --quiet crio; then
            log_info "✓ CRI-O is running"
            crio --version | while IFS= read -r line; do
                log_info "  $line"
            done
        else
            log_error "CRI-O failed to start"
            exit 1
        fi
        ;;
esac

# Add Kubernetes repository
log_info "Adding Kubernetes repository..."

K8S_REPO="/etc/yum.repos.d/kubernetes.repo"

cat > "$K8S_REPO" <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

log_info "✓ Kubernetes repository added"
((CONFIGS_APPLIED++))

# Install Kubernetes packages
log_info "Installing Kubernetes packages..."

if $PKG_MGR install -y kubelet kubeadm kubectl --disableexcludes=kubernetes; then
    log_info "✓ Kubernetes packages installed"
    ((CONFIGS_APPLIED++))
else
    log_error "Failed to install Kubernetes packages"
    exit 1
fi

# Enable kubelet (but don't start yet - needs kubeadm init/join)
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
log_info "Runtime status: $(systemctl is-active $CONTAINER_RUNTIME 2>/dev/null || echo 'not running')"
log_info "Kubernetes version: $(kubelet --version | awk '{print $2}')"
log_info "Swap status: $([ $(swapon --show | wc -l) -eq 0 ] && echo 'disabled' || echo 'enabled')"
log_info "SELinux mode: $(getenforce 2>/dev/null || echo 'disabled')"
log_info "Configurations applied: $CONFIGS_APPLIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Kubernetes node preparation completed!"
log_info ""
log_info "Next steps:"
log_info "  Control plane: kubeadm init --pod-network-cidr=10.244.0.0/16"
log_info "  Worker node: kubeadm join <control-plane-endpoint> --token <token> --discovery-token-ca-cert-hash <hash>"
log_info ""
log_info "After cluster initialization:"
log_info "  - Deploy CNI plugin (Calico, Flannel, Weave, etc.)"
log_info "  - Verify nodes: kubectl get nodes"
log_info "  - Verify pods: kubectl get pods --all-namespaces"