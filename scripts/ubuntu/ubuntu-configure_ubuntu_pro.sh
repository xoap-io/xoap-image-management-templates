#!/bin/bash
#===================================================================================
# Script: ubuntu-configure_ubuntu_pro.sh
# Description: Configure Ubuntu Pro (formerly Ubuntu Advantage)
# Author: XOAP Infrastructure Team
# Usage: ./ubuntu-configure_ubuntu_pro.sh --token YOUR_TOKEN
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
PRO_TOKEN=""
ENABLE_SERVICES="esm-infra esm-apps"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            PRO_TOKEN="$2"
            shift 2
            ;;
        --services)
            ENABLE_SERVICES="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            log_error "Usage: $0 --token YOUR_TOKEN [--services 'service1 service2']"
            exit 1
            ;;
    esac
done

if [[ -z "$PRO_TOKEN" ]]; then
    log_error "Ubuntu Pro token is required"
    log_error "Usage: $0 --token YOUR_TOKEN [--services 'service1 service2']"
    exit 1
fi

log_info "Starting Ubuntu Pro configuration..."

# Statistics tracking
START_TIME=$(date +%s)
SERVICES_ENABLED=0

# Update package lists
apt-get update -qq

# Install ubuntu-advantage-tools if not present
if ! command -v pro &>/dev/null; then
    log_info "Installing ubuntu-advantage-tools..."
    
    if DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-advantage-tools; then
        log_info "✓ ubuntu-advantage-tools installed"
    else
        log_error "Failed to install ubuntu-advantage-tools"
        exit 1
    fi
else
    log_info "ubuntu-advantage-tools is already installed"
fi

# Get installed version
UA_VERSION=$(pro version 2>/dev/null | head -n 1 || echo "unknown")
log_info "Ubuntu Pro client version: $UA_VERSION"

# Check current status
log_info "Checking current Ubuntu Pro status..."

if pro status 2>/dev/null | grep -q "This machine is attached"; then
    log_warn "Machine is already attached to Ubuntu Pro"
    log_info "Current status:"
    pro status 2>/dev/null | head -n 20 | while IFS= read -r line; do
        log_info "  $line"
    done
    
    log_warn "Detaching from current subscription..."
    if pro detach --assume-yes; then
        log_info "✓ Detached from previous subscription"
    else
        log_error "Failed to detach from previous subscription"
        exit 1
    fi
fi

# Attach to Ubuntu Pro
log_info "Attaching to Ubuntu Pro subscription..."

if pro attach "$PRO_TOKEN"; then
    log_info "✓ Successfully attached to Ubuntu Pro"
else
    log_error "Failed to attach to Ubuntu Pro"
    exit 1
fi

# Enable requested services
log_info "Enabling Ubuntu Pro services: $ENABLE_SERVICES"

for service in $ENABLE_SERVICES; do
    log_info "Enabling service: $service..."
    
    if pro enable "$service" --assume-yes; then
        log_info "✓ $service enabled"
        ((SERVICES_ENABLED++))
    else
        log_warn "Failed to enable $service"
    fi
done

# Display final status
log_info ""
log_info "Ubuntu Pro configuration status:"
log_info "=============================================="

pro status 2>/dev/null | while IFS= read -r line; do
    log_info "$line"
done

# Get service details
log_info ""
log_info "Enabled services:"

pro status --format json 2>/dev/null | grep -E '"name"|"status"' | paste - - | while IFS= read -r line; do
    log_info "  $line"
done || pro status 2>/dev/null | grep -A 1 "SERVICE" | tail -n +2 | while IFS= read -r line; do
    log_info "  $line"
done

# Update package lists to include Pro repositories
log_info ""
log_info "Updating package lists with Pro repositories..."

if apt-get update -qq; then
    log_info "✓ Package lists updated"
else
    log_warn "Failed to update package lists"
fi

# Check for additional updates from Pro
log_info "Checking for updates from Ubuntu Pro repositories..."

UPGRADABLE_PRO=$(apt list --upgradable 2>/dev/null | grep -i "ubuntu-pro\|esm" | wc -l || echo "0")

if [[ $UPGRADABLE_PRO -gt 0 ]]; then
    log_info "$UPGRADABLE_PRO package(s) available from Ubuntu Pro repositories"
else
    log_info "No additional Pro updates available"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

ATTACHED_STATUS=$(pro status 2>/dev/null | grep -q "This machine is attached" && echo "attached" || echo "not attached")
ENABLED_COUNT=$(pro status 2>/dev/null | grep -c "enabled" || echo "0")

log_info ""
log_info "=============================================="
log_info "Ubuntu Pro Configuration Summary"
log_info "=============================================="
log_info "Client version: $UA_VERSION"
log_info "Attachment status: $ATTACHED_STATUS"
log_info "Services enabled: $SERVICES_ENABLED"
log_info "Total enabled services: $ENABLED_COUNT"
log_info "Pro updates available: $UPGRADABLE_PRO"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Ubuntu Pro configuration completed!"
log_info ""
log_info "Ubuntu Pro commands:"
log_info "  - Status: pro status"
log_info "  - Enable service: pro enable SERVICE_NAME"
log_info "  - Disable service: pro disable SERVICE_NAME"
log_info "  - Detach: pro detach"
log_info "  - Refresh: pro refresh"