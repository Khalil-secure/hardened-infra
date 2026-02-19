#!/bin/bash
echo "[*] Starting hardened server..."

# Start logging
rsyslogd

# Fix permissions
chmod 666 /var/log/auth.log /var/log/syslog

# Start SSH
mkdir -p /run/sshd
service ssh start

# Start Fail2ban
service fail2ban start

# Start file integrity monitoring
inotifywait -m -e modify,attrib,move,create,delete \
  /etc/passwd \
  /etc/shadow \
  /etc/ssh/sshd_config \
  >> /var/log/file-monitor.log 2>&1 &

echo "[*] All services running"
echo "[*] SSH on port 2222"
echo "[*] Fail2ban active"
echo "[*] File integrity monitoring active"

# Keep container alive and tail logs
tail -f /var/log/auth.log /var/log/fail2ban.log