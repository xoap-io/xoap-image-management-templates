#!/bin/bash
#===================================================================================
# Script: ubuntu-optimize.sh
# Description: System optimization for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./ubuntu-optimize.sh
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

log_info "Starting system optimization for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
OPTIMIZATIONS_APPLIED=0

# Detect virtualization platform
VIRT_PLATFORM=$(systemd-detect-virt 2>/dev/null || echo "none")
log_info "Detected virtualization platform: $VIRT_PLATFORM"

# Optimize swappiness for virtual machines
log_info "Optimizing swappiness..."

CURRENT_SWAPPINESS=$(cat /proc/sys/vm/swappiness)
log_info "Current swappiness: $CURRENT_SWAPPINESS"

if [[ "$VIRT_PLATFORM" != "none" ]] && [[ "$CURRENT_SWAPPINESS" -gt 10 ]]; then
    log_info "Adjusting swappiness for virtual machine..."
    echo "vm.swappiness = 10" > /etc/sysctl.d/99-vm-swappiness.conf
    sysctl -w vm.swappiness=10 &>/dev/null || log_warn "Failed to set swappiness"
    log_info "✓ Swappiness set to 10"
    ((OPTIMIZATIONS_APPLIED++))
elif [[ "$VIRT_PLATFORM" == "none" ]] && [[ "$CURRENT_SWAPPINESS" -ne 60 ]]; then
    log_info "Setting default swappiness for physical machine..."
    echo "vm.swappiness = 60" > /etc/sysctl.d/99-vm-swappiness.conf
    sysctl -w vm.swappiness=60 &>/dev/null || log_warn "Failed to set swappiness"
    log_info "✓ Swappiness set to 60"
    ((OPTIMIZATIONS_APPLIED++))
else
    log_info "Swappiness already optimized"
fi

# Optimize I/O scheduler
log_info "Optimizing I/O scheduler..."

for disk in /sys/block/sd*/queue/scheduler /sys/block/vd*/queue/scheduler /sys/block/nvme*/queue/scheduler; do
    if [[ -f "$disk" ]]; then
        DEVICE=$(echo "$disk" | cut -d'/' -f4)
        SCHEDULER=$(cat "$disk" | grep -oP '\[\K[^\]]+')
        
        log_info "  $DEVICE: current scheduler = $SCHEDULER"
        
        # Set appropriate scheduler based on device type
        if [[ "$DEVICE" == nvme* ]]; then
            # NVMe devices benefit from none or kyber
            echo "none" > "$disk" 2>/dev/null || echo "kyber" > "$disk" 2>/dev/null || true
        elif [[ "$DEVICE" == vd* ]]; then
            # Virtual disks benefit from mq-deadline or noop
            echo "mq-deadline" > "$disk" 2>/dev/null || echo "deadline" > "$disk" 2>/dev/null || true
        else
            # Physical SATA/SAS disks benefit from mq-deadline
            echo "mq-deadline" > "$disk" 2>/dev/null || echo "deadline" > "$disk" 2>/dev/null || true
        fi
        
        NEW_SCHEDULER=$(cat "$disk" | grep -oP '\[\K[^\]]+')
        log_info "  $DEVICE: new scheduler = $NEW_SCHEDULER"
    fi
done

((OPTIMIZATIONS_APPLIED++))

# Optimize systemd settings
log_info "Optimizing systemd settings..."

mkdir -p /etc/systemd/system.conf.d

cat > /etc/systemd/system.conf.d/99-optimization.conf <<'EOF'
[Manager]
DefaultTimeoutStartSec=90s
DefaultTimeoutStopSec=30s
DefaultLimitNOFILE=65536
DefaultLimitNPROC=4096
EOF

systemctl daemon-reload

log_info "✓ systemd settings optimized"
((OPTIMIZATIONS_APPLIED++))

# Optimize journald
log_info "Optimizing journald settings..."

mkdir -p /etc/systemd/journald.conf.d

cat > /etc/systemd/journald.conf.d/99-optimization.conf <<'EOF'
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=7day
MaxFileSec=1day
Compress=yes
EOF

systemctl restart systemd-journald

log_info "✓ journald settings optimized"
((OPTIMIZATIONS_APPLIED++))

# Optimize network parameters
log_info "Optimizing network parameters..."

cat > /etc/sysctl.d/99-network-optimization.conf <<'EOF'
# Network Performance Optimization

# Increase TCP buffer sizes
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Enable TCP window scaling
net.ipv4.tcp_window_scaling = 1

# Increase connection backlog
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192

# TCP keepalive settings
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Enable timestamps
net.ipv4.tcp_timestamps = 1

# Enable selective acknowledgments
net.ipv4.tcp_sack = 1

# Disable TCP slow start after idle
net.ipv4.tcp_slow_start_after_idle = 0
EOF

sysctl -p /etc/sysctl.d/99-network-optimization.conf &>/dev/null

log_info "✓ Network parameters optimized"
((OPTIMIZATIONS_APPLIED++))

# Optimize file system settings
log_info "Optimizing file system settings..."

cat > /etc/sysctl.d/99-fs-optimization.conf <<'EOF'
# File System Optimization

# Increase file handle limits
fs.file-max = 2097152

# Increase inotify limits
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
fs.inotify.max_queued_events = 32768
EOF

sysctl -p /etc/sysctl.d/99-fs-optimization.conf &>/dev/null

log_info "✓ File system settings optimized"
((OPTIMIZATIONS_APPLIED++))

# Disable unnecessary services (safe to disable)
log_info "Checking for unnecessary services..."

UNNECESSARY_SERVICES=(
    "apt-daily.timer"
    "apt-daily-upgrade.timer"
    "motd-news.timer"
)

for service in "${UNNECESSARY_SERVICES[@]}"; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl disable --quiet "$service" 2>/dev/null || true
        systemctl stop "$service" 2>/dev/null || true
        log_info "  ✓ Disabled $service"
    fi
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "System Optimization Summary"
log_info "=============================================="
log_info "Virtualization platform: $VIRT_PLATFORM"
log_info "Swappiness: $(cat /proc/sys/vm/swappiness)"
log_info "Optimizations applied: $OPTIMIZATIONS_APPLIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "System optimization completed!"
log_info ""
log_info "Optimization details:"
log_info "  - Swappiness adjusted for ${VIRT_PLATFORM}"
log_info "  - I/O schedulers optimized"
log_info "  - systemd timeout settings reduced"
log_info "  - journald configured for efficient logging"
log_info "  - Network parameters tuned for performance"
log_info "  - File system limits increased"