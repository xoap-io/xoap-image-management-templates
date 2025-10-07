#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Use-Pty=0 -o Acquire::Retries=3)

apt-get update "${APT_OPTS[@]}"
apt-get dist-upgrade "${APT_OPTS[@]}"
apt-get autoremove --purge -y
apt-get autoclean -y
apt-get clean -y
