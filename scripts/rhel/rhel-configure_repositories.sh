#!/bin/bash
#===================================================================================
# Script: configure_repositories.sh
# Description: Configure package repositories for RHEL/CentOS
# Author: XOAP Infrastructure Team
# Usage: ./configure_repositories.sh
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

log_info "Starting repository configuration..."

# Statistics tracking
START_TIME=$(date +%s)
REPOS_ENABLED=0
REPOS_DISABLED=0
REPOS_ADDED=0

# Detect distribution
if [[ -f /etc/redhat-release ]]; then
    DISTRO=$(cat /etc/redhat-release)
    log_info "Detected: $DISTRO"
else
    log_error "Not a RHEL-based distribution"
    exit 1
fi

# Determine package manager
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    log_error "No supported package manager found"
    exit 1
fi

log_info "Using package manager: $PKG_MGR"

# List current repositories
log_info "Current repositories:"
$PKG_MGR repolist all | while IFS= read -r line; do
    log_info "  $line"
done

# Install EPEL repository (if not already installed)
log_info "Checking for EPEL repository..."

if ! rpm -q epel-release &>/dev/null; then
    log_info "EPEL repository not found. Installing..."
    
    if $PKG_MGR install -y epel-release 2>&1 | tee -a /tmp/repo-config.log; then
        log_info "EPEL repository installed successfully"
        REPOS_ADDED=$((REPOS_ADDED + 1))
    else
        log_warn "Failed to install EPEL repository"
    fi
else
    log_info "EPEL repository is already installed"
fi

# Enable PowerTools/CRB repository (for Rocky/Alma 8+)
log_info "Checking for PowerTools/CRB repository..."

if $PKG_MGR repolist all 2>/dev/null | grep -qi "powertools\|crb"; then
    POWERTOOLS_REPO=$($PKG_MGR repolist all 2>/dev/null | grep -i "powertools\|crb" | awk '{print $1}' | head -1 || echo "")
    
    if [[ -n "$POWERTOOLS_REPO" ]]; then
        log_info "Enabling $POWERTOOLS_REPO..."
        
        if $PKG_MGR config-manager --set-enabled "$POWERTOOLS_REPO" 2>&1 | tee -a /tmp/repo-config.log; then
            log_info "PowerTools/CRB repository enabled"
            REPOS_ENABLED=$((REPOS_ENABLED + 1))
        else
            log_warn "Failed to enable PowerTools/CRB repository"
        fi
    fi
else
    log_info "PowerTools/CRB repository not available on this system"
fi

# Disable unwanted repositories (optional)
REPOS_TO_DISABLE=(
    "*-debug-rpms"
    "*-source-rpms"
)

log_info "Disabling debug and source repositories..."
for repo_pattern in "${REPOS_TO_DISABLE[@]}"; do
    MATCHING_REPOS=$($PKG_MGR repolist all 2>/dev/null | grep -E "$repo_pattern" | awk '{print $1}' || echo "")
    
    if [[ -n "$MATCHING_REPOS" ]]; then
        while IFS= read -r repo; do
            if [[ -n "$repo" ]]; then
                log_info "Disabling: $repo"
                
                if $PKG_MGR config-manager --set-disabled "$repo" 2>/dev/null; then
                    REPOS_DISABLED=$((REPOS_DISABLED + 1))
                fi
            fi
        done <<< "$MATCHING_REPOS"
    fi
done

# Clean and update repository cache
log_info "Cleaning repository cache..."
$PKG_MGR clean all

log_info "Updating repository metadata..."
$PKG_MGR makecache 2>&1 | tee -a /tmp/repo-config.log

# List final repositories
log_info "Final enabled repositories:"
$PKG_MGR repolist enabled | while IFS= read -r line; do
    log_info "  $line"
done

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "Repository Configuration Summary"
log_info "=============================================="
log_info "Repositories added: $REPOS_ADDED"
log_info "Repositories enabled: $REPOS_ENABLED"
log_info "Repositories disabled: $REPOS_DISABLED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Repository configuration completed successfully!"