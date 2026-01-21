#!/bin/bash
#===================================================================================
# Script: remove-dvd-source_suse.sh
# Description: Remove DVD/ISO source repositories from SUSE Linux
# Author: XOAP Infrastructure Team
# Usage: ./remove-dvd-source_suse.sh
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

# Error handler (non-fatal - script should always succeed)
error_exit() {
    log_error "Script encountered error at line $1"
    log_warn "Continuing execution (DVD source removal is non-critical)..."
}

trap 'error_exit $LINENO' ERR

# Root check
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting DVD source repository removal..."

# Statistics tracking
START_TIME=$(date +%s)
REPOS_REMOVED=0
REPOS_FAILED=0

# Check if zypper is available
if ! command -v zypper &>/dev/null; then
    log_error "zypper command not found - not a SUSE-based system?"
    exit 0  # Non-fatal for compatibility
fi

# List current repositories
log_info "Current repositories:"
zypper repos --uri 2>/dev/null | tail -n +3 | while IFS= read -r line; do
    log_info "  $line"
done

# Find SLES DVD/ISO repositories
log_info "Searching for SLES DVD/ISO repositories..."

# Extract SLES repository names
SLES_REPOS=$(zypper repos 2>/dev/null | grep -i 'SLES' | awk '{print $3}' | grep "^SLES" || echo "")

if [[ -z "$SLES_REPOS" ]]; then
    log_info "No SLES DVD/ISO repositories found"
    log_info "Repository removal not required"
else
    REPO_COUNT=$(echo "$SLES_REPOS" | wc -l)
    log_info "Found $REPO_COUNT SLES repository/repositories:"
    
    echo "$SLES_REPOS" | while IFS= read -r repo; do
        log_info "  - $repo"
    done
    
    # Remove each SLES repository
    log_info "Removing SLES DVD/ISO repositories..."
    
    echo "$SLES_REPOS" | while IFS= read -r repo; do
        if [[ -n "$repo" ]]; then
            log_info "Removing repository: $repo"
            
            if zypper --non-interactive removerepo "$repo" 2>&1 | tee -a /tmp/zypper-dvd-removal.log; then
                log_info "Successfully removed: $repo"
                REPOS_REMOVED=$((REPOS_REMOVED + 1))
            else
                log_warn "Failed to remove repository: $repo"
                REPOS_FAILED=$((REPOS_FAILED + 1))
            fi
        fi
    done
fi

# Also remove any repositories with DVD/CD/ISO in the URI
log_info "Checking for DVD/CD/ISO mount point repositories..."

DVD_MOUNT_REPOS=$(zypper repos --uri 2>/dev/null | grep -iE '(dvd|cdrom|iso|sr[0-9])' | awk '{print $1}' || echo "")

if [[ -n "$DVD_MOUNT_REPOS" ]]; then
    DVD_COUNT=$(echo "$DVD_MOUNT_REPOS" | wc -l)
    log_info "Found $DVD_COUNT DVD/CD/ISO mount point repository/repositories"
    
    echo "$DVD_MOUNT_REPOS" | while IFS= read -r repo_num; do
        if [[ -n "$repo_num" && "$repo_num" =~ ^[0-9]+$ ]]; then
            # Get repository name
            REPO_NAME=$(zypper repos 2>/dev/null | awk -v num="$repo_num" '$1 == num {print $3}')
            
            if [[ -n "$REPO_NAME" ]]; then
                log_info "Removing DVD mount repository: $REPO_NAME (ID: $repo_num)"
                
                if zypper --non-interactive removerepo "$REPO_NAME" 2>&1 | tee -a /tmp/zypper-dvd-removal.log; then
                    log_info "Successfully removed: $REPO_NAME"
                    REPOS_REMOVED=$((REPOS_REMOVED + 1))
                else
                    log_warn "Failed to remove repository: $REPO_NAME"
                    REPOS_FAILED=$((REPOS_FAILED + 1))
                fi
            fi
        fi
    done
else
    log_info "No DVD/CD/ISO mount point repositories found"
fi

# Refresh repository list
log_info "Refreshing repository list..."
if zypper --non-interactive refresh 2>&1 | tee -a /tmp/zypper-refresh.log; then
    log_info "Repository refresh completed successfully"
else
    log_warn "Repository refresh completed with warnings (may be normal)"
fi

# List final repositories
log_info "Final repository configuration:"
zypper repos --uri 2>/dev/null | tail -n +3 | while IFS= read -r line; do
    log_info "  $line"
done

# Verify no SLES DVD repositories remain
log_info "Verifying DVD repository removal..."
REMAINING_SLES=$(zypper repos 2>/dev/null | grep -i 'SLES' | grep "^SLES" | wc -l || echo "0")

if [[ $REMAINING_SLES -eq 0 ]]; then
    log_info "✓ All SLES DVD repositories successfully removed"
else
    log_warn "✗ Some SLES repositories may still remain: $REMAINING_SLES"
fi

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "DVD Repository Removal Summary"
log_info "=============================================="
log_info "Repositories removed: $REPOS_REMOVED"
log_info "Removal failures: $REPOS_FAILED"
log_info "Remaining SLES repos: $REMAINING_SLES"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="

if [[ $REPOS_REMOVED -gt 0 ]]; then
    log_info "DVD source repository removal completed successfully!"
else
    log_info "No DVD repositories were removed (none found or already removed)"
fi

# Always exit successfully (DVD removal is non-critical)
exit 0
