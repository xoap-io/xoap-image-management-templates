#!/bin/bash
#===================================================================================
# Script: cleanup_suse.sh
# Description: Comprehensive cleanup for SUSE Linux image preparation
# Author: XOAP Infrastructure Team
# Usage: ./cleanup_suse.sh
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

log_info "Starting SUSE Linux image cleanup..."

# Statistics tracking
START_TIME=$(date +%s)
DISK_BEFORE=$(df / | awk 'NR==2 {print $3}')
TASKS_COMPLETED=0
TASKS_FAILED=0

# Function to calculate directory size
get_dir_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo "0"
    else
        echo "0"
    fi
}

#===================================================================================
# Task 1: Remove unnecessary packages
#===================================================================================
log_info "[Task 1/10] Removing unnecessary packages..."

PACKAGES_TO_REMOVE=(
    "gcc"
    "kernel-default-devel"
    "wallpaper-branding"
    "release-notes"
    "sound-theme-freedesktop"
)

PACKAGES_REMOVED=0
for package in "${PACKAGES_TO_REMOVE[@]}"; do
    if rpm -q "$package" &>/dev/null; then
        log_info "Removing package: $package"
        if zypper --non-interactive remove --clean-deps "$package" 2>&1 | tee -a /tmp/package-removal.log; then
            PACKAGES_REMOVED=$((PACKAGES_REMOVED + 1))
            log_info "Successfully removed: $package"
        else
            log_warn "Failed to remove package: $package (may not be critical)"
        fi
    else
        log_info "Package not installed: $package (skipping)"
    fi
done

log_info "Removed $PACKAGES_REMOVED packages"
TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 2: Clean zypper cache
#===================================================================================
log_info "[Task 2/10] Cleaning zypper package cache..."

CACHE_SIZE_BEFORE=$(get_dir_size "/var/cache/zypp")

if zypper clean --all 2>&1 | tee -a /tmp/zypper-clean.log; then
    log_info "Zypper cache cleaned successfully"
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    
    CACHE_SIZE_AFTER=$(get_dir_size "/var/cache/zypp")
    CACHE_FREED=$((CACHE_SIZE_BEFORE - CACHE_SIZE_AFTER))
    
    if [[ $CACHE_FREED -gt 0 ]]; then
        log_info "Freed $(numfmt --to=iec-i --suffix=B $CACHE_FREED) from zypper cache"
    fi
else
    log_warn "Zypper cache cleaning completed with warnings"
    TASKS_FAILED=$((TASKS_FAILED + 1))
fi

#===================================================================================
# Task 3: Remove network interface persistence rules
#===================================================================================
log_info "[Task 3/10] Removing network interface persistence rules..."

UDEV_RULES=(
    "/etc/udev/rules.d/70-persistent-net.rules"
    "/etc/udev/rules.d/75-persistent-net-generator.rules"
)

for rule_file in "${UDEV_RULES[@]}"; do
    if [[ -f "$rule_file" ]]; then
        log_info "Removing: $rule_file"
        rm -f "$rule_file"
    fi
done

# Create empty generator rules file to prevent regeneration
touch /etc/udev/rules.d/75-persistent-net-generator.rules
log_info "Created empty persistent-net-generator.rules"

TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 4: Clean log files
#===================================================================================
log_info "[Task 4/10] Cleaning system log files..."

LOG_SIZE_BEFORE=$(get_dir_size "/var/log")

# Remove rotated/compressed logs
log_info "Removing rotated log files..."
ROTATED_COUNT=$(find /var/log/ -type f \( -name "*.log.*" -o -name "*.gz" -o -name "*.bz2" -o -name "*.xz" \) 2>/dev/null | wc -l)
find /var/log/ -type f \( -name "*.log.*" -o -name "*.gz" -o -name "*.bz2" -o -name "*.xz" \) -exec rm -f {} \; 2>/dev/null || true
log_info "Removed $ROTATED_COUNT rotated log files"

# Truncate current log files
log_info "Truncating active log files..."
TRUNCATED_COUNT=0
while IFS= read -r -d '' logfile; do
    truncate --size=0 "$logfile" 2>/dev/null && TRUNCATED_COUNT=$((TRUNCATED_COUNT + 1)) || true
done < <(find /var/log -type f -name "*.log" -print0 2>/dev/null)

log_info "Truncated $TRUNCATED_COUNT active log files"

LOG_SIZE_AFTER=$(get_dir_size "/var/log")
LOG_FREED=$((LOG_SIZE_BEFORE - LOG_SIZE_AFTER))

if [[ $LOG_FREED -gt 0 ]]; then
    log_info "Freed $(numfmt --to=iec-i --suffix=B $LOG_FREED) from log files"
fi

TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 5: Clean journal logs
#===================================================================================
log_info "[Task 5/10] Cleaning systemd journal logs..."

if command -v journalctl &>/dev/null; then
    JOURNAL_SIZE_BEFORE=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[MGK]' || echo "0")
    
    log_info "Current journal size: $JOURNAL_SIZE_BEFORE"
    journalctl --vacuum-time=1s 2>&1 | tee -a /tmp/journal-cleanup.log || true
    
    JOURNAL_SIZE_AFTER=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[MGK]' || echo "0")
    log_info "Journal size after cleanup: $JOURNAL_SIZE_AFTER"
fi

TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 6: Clean temporary directories
#===================================================================================
log_info "[Task 6/10] Cleaning temporary directories..."

TEMP_DIRS=(
    "/tmp"
    "/var/tmp"
)

for temp_dir in "${TEMP_DIRS[@]}"; do
    if [[ -d "$temp_dir" ]]; then
        TEMP_SIZE_BEFORE=$(get_dir_size "$temp_dir")
        log_info "Cleaning: $temp_dir"
        
        # Remove contents but not the directory itself
        find "$temp_dir" -mindepth 1 -delete 2>/dev/null || true
        
        TEMP_SIZE_AFTER=$(get_dir_size "$temp_dir")
        TEMP_FREED=$((TEMP_SIZE_BEFORE - TEMP_SIZE_AFTER))
        
        if [[ $TEMP_FREED -gt 0 ]]; then
            log_info "Freed $(numfmt --to=iec-i --suffix=B $TEMP_FREED) from $temp_dir"
        fi
    fi
done

TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 7: Reset machine-id
#===================================================================================
log_info "[Task 7/10] Resetting machine-id for unique identification..."

MACHINE_ID_FILES=(
    "/etc/machine-id"
    "/var/lib/dbus/machine-id"
)

for id_file in "${MACHINE_ID_FILES[@]}"; do
    if [[ -f "$id_file" ]]; then
        # Check if it's a symlink
        if [[ -L "$id_file" ]]; then
            log_info "Skipping symlink: $id_file"
        else
            log_info "Truncating: $id_file"
            truncate --size=0 "$id_file"
        fi
    else
        log_info "File not found: $id_file"
    fi
done

TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 8: Remove random seed
#===================================================================================
log_info "[Task 8/10] Removing random seed for regeneration..."

RANDOM_SEED_FILE="/var/lib/systemd/random-seed"
if [[ -f "$RANDOM_SEED_FILE" ]]; then
    log_info "Removing: $RANDOM_SEED_FILE"
    rm -f "$RANDOM_SEED_FILE"
    log_info "Random seed will be regenerated on next boot"
else
    log_info "Random seed file not found (may not exist on this system)"
fi

TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 9: Clean user history and caches
#===================================================================================
log_info "[Task 9/10] Cleaning user history and cache files..."

# Root user files
FILES_TO_CLEAN=(
    "/root/.bash_history"
    "/root/.wget-hsts"
    "/root/.cache"
    "/root/.local/share/recently-used.xbel"
)

for file in "${FILES_TO_CLEAN[@]}"; do
    if [[ -e "$file" ]]; then
        log_info "Removing: $file"
        rm -rf "$file"
    fi
done

# Clean history for all users
for user_home in /home/*; do
    if [[ -d "$user_home" ]]; then
        username=$(basename "$user_home")
        log_info "Cleaning history for user: $username"
        
        rm -f "$user_home/.bash_history" 2>/dev/null || true
        rm -f "$user_home/.wget-hsts" 2>/dev/null || true
        rm -rf "$user_home/.cache" 2>/dev/null || true
    fi
done

# Clear current shell history
export HISTSIZE=0
export HISTFILESIZE=0
history -c 2>/dev/null || true

log_info "User history and cache files cleaned"
TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Task 10: Clean SSH host keys (optional - uncomment if needed)
#===================================================================================
log_info "[Task 10/10] SSH host keys cleanup..."

# Note: Uncomment the following lines if you want to regenerate SSH host keys on first boot
# SSH_KEY_FILES="/etc/ssh/ssh_host_*"
# if compgen -G "$SSH_KEY_FILES" > /dev/null; then
#     log_info "Removing SSH host keys (will be regenerated on first boot)"
#     rm -f /etc/ssh/ssh_host_*
# else
#     log_info "No SSH host keys found"
# fi

log_info "SSH host keys preserved (remove manually if regeneration needed)"
TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

#===================================================================================
# Final cleanup and summary
#===================================================================================

# Get final disk usage
DISK_AFTER=$(df / | awk 'NR==2 {print $3}')
DISK_FREED=$((DISK_BEFORE - DISK_AFTER))

# Calculate execution time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "=============================================="
log_info "SUSE Linux Cleanup Summary"
log_info "=============================================="
log_info "Tasks completed: $TASKS_COMPLETED/10"
log_info "Tasks failed: $TASKS_FAILED"
log_info "Packages removed: $PACKAGES_REMOVED"

if [[ $DISK_FREED -gt 0 ]]; then
    log_info "Total disk space freed: $(numfmt --to=iec-i --suffix=B $((DISK_FREED * 1024)))"
elif [[ $DISK_FREED -lt 0 ]]; then
    log_warn "Disk usage increased: $(numfmt --to=iec-i --suffix=B $((-DISK_FREED * 1024)))"
else
    log_info "Disk space change: minimal"
fi

log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "Image cleanup completed successfully!"
log_info ""
log_info "Image is ready for template/snapshot creation"
