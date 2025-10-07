#!/bin/bash
# Optimized SSH hardening for Ubuntu 20.04

set -e

SSH_CONFIG="/etc/ssh/sshd_config"

log() {
    echo "[SSH] $1"
}

log "Applying SSH hardening..."

sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONFIG
sudo sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' $SSH_CONFIG
sudo sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' $SSH_CONFIG
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' $SSH_CONFIG
sudo sed -i 's/^#\?UsePAM.*/UsePAM yes/' $SSH_CONFIG
sudo sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding no/' $SSH_CONFIG
sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' $SSH_CONFIG
sudo sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 30/' $SSH_CONFIG
sudo sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' $SSH_CONFIG
sudo sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' $SSH_CONFIG

# Ensure settings exist if not present
sudo grep -q '^PermitRootLogin' $SSH_CONFIG || echo 'PermitRootLogin no' | sudo tee -a $SSH_CONFIG
sudo grep -q '^PasswordAuthentication' $SSH_CONFIG || echo 'PasswordAuthentication no' | sudo tee -a $SSH_CONFIG
sudo grep -q '^X11Forwarding' $SSH_CONFIG || echo 'X11Forwarding no' | sudo tee -a $SSH_CONFIG
sudo grep -q '^PermitEmptyPasswords' $SSH_CONFIG || echo 'PermitEmptyPasswords no' | sudo tee -a $SSH_CONFIG
sudo grep -q '^ChallengeResponseAuthentication' $SSH_CONFIG || echo 'ChallengeResponseAuthentication no' | sudo tee -a $SSH_CONFIG
sudo grep -q '^UsePAM' $SSH_CONFIG || echo 'UsePAM yes' | sudo tee -a $SSH_CONFIG
sudo grep -q '^AllowTcpForwarding' $SSH_CONFIG || echo 'AllowTcpForwarding no' | sudo tee -a $SSH_CONFIG
sudo grep -q '^MaxAuthTries' $SSH_CONFIG || echo 'MaxAuthTries 3' | sudo tee -a $SSH_CONFIG
sudo grep -q '^LoginGraceTime' $SSH_CONFIG || echo 'LoginGraceTime 30' | sudo tee -a $SSH_CONFIG
sudo grep -q '^ClientAliveInterval' $SSH_CONFIG || echo 'ClientAliveInterval 300' | sudo tee -a $SSH_CONFIG
sudo grep -q '^ClientAliveCountMax' $SSH_CONFIG || echo 'ClientAliveCountMax 2' | sudo tee -a $SSH_CONFIG

log "Reloading SSH daemon..."
sudo systemctl reload sshd

log "SSH hardening applied."
