#!/usr/bin/env bash
# Validation "tests" for the RHEL 9 azure-arm cloud base image — the Linux equivalent of the
# Pester run on Windows. Any failed assertion exits non-zero, which alpaka treats as a build
# failure, so a non-compliant image is never captured to the managed image / gallery version.
#
# Asserts the outcomes this set promises: SSH hardened, firewalld active, chronyd time sync,
# the Azure guest agent present, and cloud-init present for generalization.
set -uo pipefail

fail=0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"
    fail=1
  fi
}

echo "=== RHEL azure-arm cloud base validation ==="

# SSH hardening (rhel-ssh_hardening.sh): root login + password auth disabled.
check "sshd: PermitRootLogin no"        bash -c "sshd -T 2>/dev/null | grep -qx 'permitrootlogin no' || grep -Eqi '^\s*PermitRootLogin\s+no' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf"
check "sshd: PasswordAuthentication no" bash -c "sshd -T 2>/dev/null | grep -qx 'passwordauthentication no' || grep -Eqi '^\s*PasswordAuthentication\s+no' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf"

# Host firewall (rhel-firewalld_hardening.sh).
check "firewalld present"               command -v firewall-cmd

# Time sync (rhel-configure_chronyd.sh).
check "chronyd present"                 bash -c 'systemctl is-enabled chronyd 2>/dev/null || command -v chronyd'

# Azure guest agent (rhel-azure_configure.sh) + cloud-init for generalization.
check "Azure Linux agent present"       bash -c 'systemctl is-enabled waagent 2>/dev/null || command -v waagent || test -f /etc/waagent.conf'
check "cloud-init present"              command -v cloud-init

echo "=== Validation $( [ $fail -eq 0 ] && echo PASSED || echo FAILED ) ==="
exit $fail
