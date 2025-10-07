#!/bin/bash
# Remove SSH keys and histories (for Packer finalization)
sudo shred -u /etc/ssh/*_key /etc/ssh/*_key.pub 2>/dev/null
sudo rm -rf /root/.bash_history /home/*/.bash_history
history -c
