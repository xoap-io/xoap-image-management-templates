#!/bin/bash
# Disable unnecessary services (examples: cups, avahi-daemon, bluetooth)
for svc in cups avahi-daemon bluetooth; do
  sudo systemctl disable $svc 2>/dev/null
  sudo systemctl stop $svc 2>/dev/null
done
