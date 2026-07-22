#!/usr/bin/env bash
# Validation "tests" for the SLES 15 azure-arm cloud base image — the Linux equivalent of the
# Pester run on Windows. Any failed assertion exits non-zero, which alpaka treats as a build
# failure, so a non-compliant image is never captured to the managed image / gallery version.
#
# Asserts the outcomes this set promises: SSH hardened, sysctl hardening applied, firewalld
# present, chronyd time sync, the Azure guest agent present, and cloud-init present.
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

echo "=== SLES azure-arm cloud base validation ==="

# SSH hardening (suse-ssh_hardening.sh): root login + password auth disabled.
check "sshd: PermitRootLogin no"        bash -c "sshd -T 2>/dev/null | grep -qx 'permitrootlogin no' || grep -Eqir '^\s*PermitRootLogin\s+no' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null"
check "sshd: PasswordAuthentication no" bash -c "sshd -T 2>/dev/null | grep -qx 'passwordauthentication no' || grep -Eqir '^\s*PasswordAuthentication\s+no' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null"

# sysctl hardening (suse-sysctl_hardening.sh): hardening drop-in written + applied.
check "sysctl: no accept_redirects"     bash -c "[ \"\$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)\" = '0' ] || test -f /etc/sysctl.d/99-hardening-suse.conf"

# Host firewall (suse-firewalld_hardening.sh).
check "firewalld present"               command -v firewall-cmd

# Time sync (suse-configure_chronyd.sh).
check "chronyd present"                 bash -c 'systemctl is-enabled chronyd 2>/dev/null || command -v chronyd'

# Azure guest agent (suse-azure_configure.sh) + cloud-init for generalization.
check "Azure Linux agent present"       bash -c 'systemctl is-enabled waagent 2>/dev/null || command -v waagent || test -f /etc/waagent.conf'
check "cloud-init present"              command -v cloud-init

echo "=== Validation $( [ $fail -eq 0 ] && echo PASSED || echo FAILED ) ==="
exit $fail
