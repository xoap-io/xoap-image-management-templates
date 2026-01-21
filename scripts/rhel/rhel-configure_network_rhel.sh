#!/bin/bash
#===================================================================================
# Script: configure_network_rhel.sh
# Description: Configure NetworkManager and network settings for RHEL
# Author: XOAP Infrastructure Team
# Usage: ./configure_network_rhel.sh [--interface INTERFACE] [--static] [--ip IP] [--gateway GW] [--dns DNS]
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
INTERFACE="${INTERFACE:-}"
STATIC_IP="${STATIC_IP:-false}"
IP_ADDRESS="${IP_ADDRESS:-}"
GATEWAY="${GATEWAY:-}"
DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
NETMASK="${NETMASK:-24}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interface)
            INTERFACE="$2"
            shift 2
            ;;
        --static)
            STATIC_IP="true"
            shift
            ;;
        --ip)
            IP_ADDRESS="$2"
            shift 2
            ;;
        --gateway)
            GATEWAY="$2"
            shift 2
            ;;
        --dns)
            DNS_SERVERS="$2"
            shift 2
            ;;
        --netmask)
            NETMASK="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting NetworkManager configuration..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_MODIFIED=0

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

# Install NetworkManager if not present
if ! command -v nmcli &>/dev/null; then
    log_info "Installing NetworkManager..."
    
    if $PKG_MGR install -y NetworkManager; then
        log_info "✓ NetworkManager installed"
        ((CONFIGS_MODIFIED++))
    else
        log_error "Failed to install NetworkManager"
        exit 1
    fi
else
    log_info "NetworkManager is already installed"
fi

# Enable and start NetworkManager
log_info "Enabling NetworkManager service..."

systemctl enable NetworkManager
systemctl start NetworkManager

if systemctl is-active --quiet NetworkManager; then
    log_info "✓ NetworkManager is running"
else
    log_error "Failed to start NetworkManager"
    exit 1
fi

# Detect primary interface if not specified
if [[ -z "$INTERFACE" ]]; then
    log_info "Detecting primary network interface..."
    
    # Try to find the default route interface
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [[ -z "$INTERFACE" ]]; then
        # Fallback to first active interface
        INTERFACE=$(ip link show | grep -E "^[0-9]+: (eth|ens|enp)" | head -n1 | awk -F': ' '{print $2}')
    fi
    
    if [[ -z "$INTERFACE" ]]; then
        log_error "Could not detect network interface"
        log_info "Available interfaces:"
        ip link show | grep "^[0-9]" | while IFS= read -r line; do
            log_info "  $line"
        done
        exit 1
    fi
    
    log_info "Detected interface: $INTERFACE"
fi

# Verify interface exists
if ! ip link show "$INTERFACE" &>/dev/null; then
    log_error "Interface '$INTERFACE' does not exist"
    exit 1
fi

# Get current interface information
log_info "Current interface configuration:"
log_info "  Interface: $INTERFACE"
log_info "  Status: $(ip link show "$INTERFACE" | grep -o "state [A-Z]*" | awk '{print $2}')"

CURRENT_IP=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -n1 || echo "none")
log_info "  Current IP: $CURRENT_IP"

CURRENT_GW=$(ip route | grep default | grep "$INTERFACE" | awk '{print $3}' || echo "none")
log_info "  Current Gateway: $CURRENT_GW"

# Get NetworkManager connection name
NM_CONNECTION=$(nmcli -t -f NAME,DEVICE connection show | grep ":$INTERFACE$" | cut -d':' -f1 | head -n1)

if [[ -z "$NM_CONNECTION" ]]; then
    log_info "No NetworkManager connection found for $INTERFACE, creating one..."
    
    nmcli connection add type ethernet con-name "$INTERFACE" ifname "$INTERFACE"
    NM_CONNECTION="$INTERFACE"
    ((CONFIGS_MODIFIED++))
else
    log_info "NetworkManager connection: $NM_CONNECTION"
fi

# Configure static or DHCP
if [[ "$STATIC_IP" == "true" ]]; then
    # Validate static IP configuration
    if [[ -z "$IP_ADDRESS" ]]; then
        log_error "Static IP requested but no IP address provided (use --ip)"
        exit 1
    fi
    
    if [[ -z "$GATEWAY" ]]; then
        log_error "Static IP requested but no gateway provided (use --gateway)"
        exit 1
    fi
    
    log_info "Configuring static IP address..."
    log_info "  IP: $IP_ADDRESS/$NETMASK"
    log_info "  Gateway: $GATEWAY"
    log_info "  DNS: $DNS_SERVERS"
    
    # Configure static IP
    nmcli connection modify "$NM_CONNECTION" ipv4.method manual
    nmcli connection modify "$NM_CONNECTION" ipv4.addresses "$IP_ADDRESS/$NETMASK"
    nmcli connection modify "$NM_CONNECTION" ipv4.gateway "$GATEWAY"
    nmcli connection modify "$NM_CONNECTION" ipv4.dns "$DNS_SERVERS"
    
    log_info "✓ Static IP configuration applied"
    ((CONFIGS_MODIFIED++))
else
    log_info "Configuring DHCP..."
    
    nmcli connection modify "$NM_CONNECTION" ipv4.method auto
    
    log_info "✓ DHCP configuration applied"
    ((CONFIGS_MODIFIED++))
fi

# Configure connection to autoconnect
nmcli connection modify "$NM_CONNECTION" connection.autoconnect yes
log_info "✓ Autoconnect enabled"

# Disable IPv6 (optional - uncomment if needed)
# log_info "Disabling IPv6..."
# nmcli connection modify "$NM_CONNECTION" ipv6.method disabled
# ((CONFIGS_MODIFIED++))

# Apply connection changes
log_info "Applying network configuration..."

nmcli connection down "$NM_CONNECTION" &>/dev/null || log_warn "Could not bring connection down"
sleep 2

if nmcli connection up "$NM_CONNECTION"; then
    log_info "✓ Network configuration applied"
    ((CONFIGS_MODIFIED++))
else
    log_error "Failed to bring up connection"
    exit 1
fi

# Wait for network to stabilize
sleep 3

# Verify configuration
log_info "Verifying network configuration..."

NEW_IP=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -n1 || echo "none")
NEW_GW=$(ip route | grep default | grep "$INTERFACE" | awk '{print $3}' || echo "none")

log_info "New configuration:"
log_info "  IP Address: $NEW_IP"
log_info "  Gateway: $NEW_GW"
log_info "  DNS Servers: $(nmcli -g ipv4.dns connection show "$NM_CONNECTION" || echo 'none')"

# Test connectivity
log_info "Testing network connectivity..."

if ping -c 2 -W 3 "$GATEWAY" &>/dev/null 2>&1; then
    log_info "✓ Gateway is reachable"
else
    log_warn "✗ Gateway is not reachable"
fi

if ping -c 2 -W 3 8.8.8.8 &>/dev/null 2>&1; then
    log_info "✓ Internet connectivity confirmed"
else
    log_warn "✗ No internet connectivity"
fi

# Display connection status
log_info "Connection status:"
nmcli connection show "$NM_CONNECTION" | head -n 20 | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Network Configuration Summary"
log_info "=============================================="
log_info "Interface: $INTERFACE"
log_info "Connection: $NM_CONNECTION"
log_info "Configuration mode: $([ "$STATIC_IP" == "true" ] && echo 'Static' || echo 'DHCP')"
log_info "IP Address: $NEW_IP"
log_info "Gateway: $NEW_GW"
log_info "Configurations modified: $CONFIGS_MODIFIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Network configuration completed!"