#!/bin/bash
# Comprehensive compliance/configuration report
REPORT=/tmp/compliance_report.txt
echo "==== Hostname and OS Info ====" > $REPORT
hostnamectl >> $REPORT
lsb_release -a >> $REPORT
uname -a >> $REPORT

echo "\n==== Kernel Version ====" >> $REPORT
uname -r >> $REPORT

echo "\n==== Current User and Groups ====" >> $REPORT
id >> $REPORT
getent group >> $REPORT

echo "\n==== System Users ====" >> $REPORT
cat /etc/passwd >> $REPORT

echo "\n==== Installed Packages ====" >> $REPORT
dpkg-query -l >> $REPORT

echo "\n==== Installed Snap Packages ====" >> $REPORT
snap list >> $REPORT

echo "\n==== Security Updates Status ====" >> $REPORT
apt list --upgradable 2>/dev/null | grep security >> $REPORT

echo "\n==== Running Services ====" >> $REPORT
systemctl list-units --type=service --state=running >> $REPORT

echo "\n==== Enabled/Disabled Services ====" >> $REPORT
systemctl list-unit-files --type=service >> $REPORT

echo "\n==== Firewall (UFW) Status ====" >> $REPORT
sudo ufw status >> $REPORT

echo "\n==== Firewall (iptables) Rules ====" >> $REPORT
sudo iptables -L -n -v >> $REPORT

echo "\n==== Listening Ports ====" >> $REPORT
ss -tulnp >> $REPORT

echo "\n==== SELinux/AppArmor Status ====" >> $REPORT
sestatus 2>/dev/null >> $REPORT
aa-status 2>/dev/null >> $REPORT

echo "\n==== Password Policy ====" >> $REPORT
cat /etc/login.defs >> $REPORT

echo "\n==== SSH Configuration ====" >> $REPORT
cat /etc/ssh/sshd_config >> $REPORT

echo "\n==== Sudoers Configuration ====" >> $REPORT
cat /etc/sudoers >> $REPORT

echo "\n==== Disk Encryption Status ====" >> $REPORT
lsblk >> $REPORT
cryptsetup status $(lsblk -o NAME,TYPE | awk '/crypt/ {print $1}') 2>/dev/null >> $REPORT

echo "\n==== Audit Logs (today) ====" >> $REPORT
sudo ausearch -ts today >> $REPORT

echo "\n==== Scheduled Tasks (crontab) ====" >> $REPORT
crontab -l 2>/dev/null >> $REPORT
ls /etc/cron* >> $REPORT

echo "\n==== System Resource Usage ====" >> $REPORT
free -h >> $REPORT
df -h >> $REPORT
top -b -n 1 | head -20 >> $REPORT
