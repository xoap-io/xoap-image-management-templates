#!/usr/bin/env bash
# Validation "tests" for the Ubuntu azure-arm cloud base image — the Linux equivalent of the
# Pester run on Windows. Any failed assertion exits non-zero, which alpaka treats as a build
# failure, so a non-compliant image is never captured to the managed image / gallery version.
#
# Asserts the outcomes this set promises: SSH hardened, sysctl hardening applied, chrony/time
# sync present, the Azure guest agent present, and cloud-init present for generalization.
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

echo "=== Ubuntu azure-arm cloud base validation ==="

# SSH hardening (ubuntu-ssh_hardening.sh): root login + password auth disabled.
check "sshd: PermitRootLogin no"        bash -c "sshd -T 2>/dev/null | grep -qx 'permitrootlogin no' || grep -Eqi '^\s*PermitRootLogin\s+no' /etc/ssh/sshd_config"
check "sshd: PasswordAuthentication no" bash -c "sshd -T 2>/dev/null | grep -qx 'passwordauthentication no' || grep -Eqi '^\s*PasswordAuthentication\s+no' /etc/ssh/sshd_config"

# sysctl hardening (ubuntu-sysctl_hardening.sh): IP redirects/forwarding locked down.
check "sysctl: no accept_redirects"     bash -c "[ \"\$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)\" = '0' ]"

# Time sync (ubuntu-configure_chrony.sh).
check "chrony service present"          bash -c 'systemctl is-enabled chrony 2>/dev/null || systemctl is-enabled chronyd 2>/dev/null || command -v chronyd'

# Azure guest agent (ubuntu-azure_configure.sh) + cloud-init for generalization.
check "Azure Linux agent present"       bash -c 'systemctl is-enabled walinuxagent 2>/dev/null || systemctl is-enabled waagent 2>/dev/null || command -v waagent'
check "cloud-init present"              command -v cloud-init

echo "=== Validation $( [ $fail -eq 0 ] && echo PASSED || echo FAILED ) ==="
exit $fail
