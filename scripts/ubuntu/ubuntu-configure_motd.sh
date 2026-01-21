#!/bin/bash
#===================================================================================
# Script: ubuntu-configure_motd.sh
# Description: Configure Message of the Day (MOTD) for Ubuntu
# Author: XOAP Infrastructure Team
# Usage: ./ubuntu-configure_motd.sh [--disable-defaults]
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
DISABLE_DEFAULTS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --disable-defaults)
            DISABLE_DEFAULTS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting MOTD configuration for Ubuntu..."

# Statistics tracking
START_TIME=$(date +%s)
CONFIGS_APPLIED=0

# Backup existing MOTD
if [[ -f /etc/motd ]]; then
    BACKUP_FILE="/etc/motd.backup.$(date +%Y%m%d-%H%M%S)"
    cp /etc/motd "$BACKUP_FILE"
    log_info "Backed up existing MOTD to $BACKUP_FILE"
fi

# Disable default Ubuntu MOTD scripts if requested
if [[ "$DISABLE_DEFAULTS" == true ]]; then
    log_info "Disabling default Ubuntu MOTD scripts..."
    
    DEFAULT_SCRIPTS=(
        "10-help-text"
        "50-motd-news"
        "80-esm"
        "80-livepatch"
        "91-release-upgrade"
        "95-hwe-eol"
    )
    
    for script in "${DEFAULT_SCRIPTS[@]}"; do
        if [[ -f "/etc/update-motd.d/$script" ]]; then
            chmod -x "/etc/update-motd.d/$script"
            log_info "  ✓ Disabled $script"
            ((CONFIGS_APPLIED++))
        fi
    done
    
    # Disable MOTD news service
    if systemctl is-active --quiet motd-news.timer 2>/dev/null; then
        systemctl disable --quiet motd-news.timer 2>/dev/null || true
        systemctl stop motd-news.timer 2>/dev/null || true
        log_info "  ✓ Disabled motd-news.timer"
        ((CONFIGS_APPLIED++))
    fi
fi

# Create custom MOTD header
log_info "Creating custom MOTD header..."

cat > /etc/update-motd.d/00-header <<'EOF'
#!/bin/sh
#
# XOAP Custom MOTD Header
#

[ -r /etc/lsb-release ] && . /etc/lsb-release

echo ""
echo "================================================================================"
echo "                           XOAP Infrastructure"
echo "================================================================================"
echo ""
echo "  Welcome to $(hostname)"
echo ""
echo "  OS: ${DISTRIB_DESCRIPTION}"
echo "  Kernel: $(uname -r)"
echo "  Uptime: $(uptime -p)"
echo ""
EOF

chmod +x /etc/update-motd.d/00-header
log_info "✓ Custom MOTD header created"
((CONFIGS_APPLIED++))

# Create system information MOTD script
log_info "Creating system information MOTD script..."

cat > /etc/update-motd.d/05-system-info <<'EOF'
#!/bin/sh
#
# XOAP System Information
#

echo "  System Information:"
echo "  -------------------"
echo "  Hostname:    $(hostname -f)"
echo "  IP Address:  $(hostname -I | awk '{print $1}')"
echo "  Architecture: $(uname -m)"
echo "  CPUs:        $(nproc)"
echo "  Memory:      $(free -h | awk '/^Mem:/ {print $2}') total, $(free -h | awk '/^Mem:/ {print $3}') used"
echo "  Disk Usage:  $(df -h / | awk 'NR==2 {print $5 " of " $2}')"
echo ""
EOF

chmod +x /etc/update-motd.d/05-system-info
log_info "✓ System information script created"
((CONFIGS_APPLIED++))

# Create last login MOTD script
log_info "Creating last login MOTD script..."

cat > /etc/update-motd.d/10-last-login <<'EOF'
#!/bin/sh
#
# XOAP Last Login Information
#

echo "  Last Login:"
echo "  -----------"
last -n 3 -F -w | head -n 4 | tail -n 3 | while IFS= read -r line; do
    echo "  $line"
done
echo ""
EOF

chmod +x /etc/update-motd.d/10-last-login
log_info "✓ Last login script created"
((CONFIGS_APPLIED++))

# Create security updates MOTD script
log_info "Creating security updates MOTD script..."

cat > /etc/update-motd.d/90-updates-available <<'EOF'
#!/bin/sh
#
# XOAP Updates Information
#

if [ -x /usr/lib/update-notifier/apt-check ]; then
    UPDATES=$(/usr/lib/update-notifier/apt-check 2>&1)
    REGULAR=$(echo "$UPDATES" | cut -d ';' -f 1)
    SECURITY=$(echo "$UPDATES" | cut -d ';' -f 2)
    
    if [ "$REGULAR" != "0" ] || [ "$SECURITY" != "0" ]; then
        echo "  Updates Available:"
        echo "  ------------------"
        [ "$REGULAR" != "0" ] && echo "  Regular updates:  $REGULAR"
        [ "$SECURITY" != "0" ] && echo "  Security updates: $SECURITY"
        echo ""
    fi
fi

# Check for reboot requirement
if [ -f /var/run/reboot-required ]; then
    echo "  *** System restart required ***"
    echo ""
fi
EOF

chmod +x /etc/update-motd.d/90-updates-available
log_info "✓ Updates available script created"
((CONFIGS_APPLIED++))

# Create footer MOTD script
log_info "Creating MOTD footer..."

cat > /etc/update-motd.d/99-footer <<'EOF'
#!/bin/sh
#
# XOAP Custom MOTD Footer
#

echo "================================================================================"
echo "  Documentation: https://docs.xoap.io"
echo "  Support:       support@xoap.io"
echo "================================================================================"
echo ""
EOF

chmod +x /etc/update-motd.d/99-footer
log_info "✓ Custom MOTD footer created"
((CONFIGS_APPLIED++))

# Clean old MOTD
log_info "Cleaning static MOTD file..."

> /etc/motd
log_info "✓ Static MOTD cleared"

# Test MOTD generation
log_info "Testing MOTD generation..."

if run-parts --lsbsysinit /etc/update-motd.d > /tmp/motd_test.txt 2>&1; then
    log_info "✓ MOTD generation successful"
    
    log_info ""
    log_info "Generated MOTD preview:"
    log_info "=============================================="
    cat /tmp/motd_test.txt | while IFS= read -r line; do
        log_info "$line"
    done
    log_info "=============================================="
else
    log_error "MOTD generation test failed"
    cat /tmp/motd_test.txt >&2
    exit 1
fi

# Set proper permissions
log_info "Setting MOTD permissions..."

chmod 755 /etc/update-motd.d
find /etc/update-motd.d -type f -exec chmod 644 {} \;
find /etc/update-motd.d -type f -name "[0-9]*" -exec chmod +x {} \;

log_info "✓ Permissions set"
((CONFIGS_APPLIED++))

# Summary statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

CUSTOM_SCRIPTS=$(find /etc/update-motd.d -type f -name "[0-9]*" -executable | wc -l)
DISABLED_SCRIPTS=$(find /etc/update-motd.d -type f -name "[0-9]*" ! -executable | wc -l)

log_info ""
log_info "=============================================="
log_info "MOTD Configuration Summary"
log_info "=============================================="
log_info "Default scripts disabled: $([ "$DISABLE_DEFAULTS" == true ] && echo 'yes' || echo 'no')"
log_info "Custom scripts created: 5"
log_info "Total active scripts: $CUSTOM_SCRIPTS"
log_info "Disabled scripts: $DISABLED_SCRIPTS"
log_info "Configurations applied: $CONFIGS_APPLIED"
log_info "Execution time: ${DURATION}s"
log_info "=============================================="
log_info "MOTD configuration completed!"
log_info ""
log_info "MOTD scripts location: /etc/update-motd.d/"
log_info "Test MOTD: run-parts /etc/update-motd.d"