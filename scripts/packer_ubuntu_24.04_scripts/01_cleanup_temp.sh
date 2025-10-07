#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Clean apt cache and temporary files
apt-get clean -y || true
rm -rf /tmp/* || true
rm -rf /var/tmp/* || true
