#!/bin/bash
# Remove snap packages (if desired)
sudo systemctl stop snapd
sudo apt-get purge snapd -y
