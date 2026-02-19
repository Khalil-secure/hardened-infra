# Hardened Infrastructure & Security Monitoring Lab

A hands-on cybersecurity project demonstrating Linux server hardening, 
intrusion detection, and real-time monitoring using Docker containers.

## Architecture
```
[hardened-server]                    [monitor]
  - Ubuntu 22.04 (hardened)    <-->   - Netdata (real-time metrics)
  - SSH hardened (port 2222)          - Centralized log management
  - Fail2ban (IDS/brute force)        - Auth/Fail2ban log monitoring
  - File integrity monitoring         
  Both isolated on private Docker network (hardened-net)
```

## Security Layers Implemented

### 1. SSH Hardening
- Custom port (2222) to avoid automated scanners
- Root login disabled
- Key-based authentication only (passwords disabled)
- MaxAuthTries limited to 3
- LoginGraceTime set to 30 seconds
- TCP and X11 forwarding disabled

### 2. Intrusion Detection (Fail2ban)
- Monitors auth.log in real time
- Bans IPs after 3 failed SSH attempts
- 1 hour ban duration
- Tested and verified live

### 3. File Integrity Monitoring (inotifywait)
- Watches /etc/passwd, /etc/shadow, /etc/ssh/sshd_config
- Logs any modification, creation, or deletion
- Alerts written to /var/log/file-monitor.log

### 4. Centralized Log Management
- auth.log, fail2ban.log, file-monitor.log shared via Docker volume
- Monitor container reads all logs in real time
- Netdata dashboard on port 19999

## How to Run
```bash
# Create the network
docker network create hardened-net

# Create shared log volume
docker volume create hardened-logs

# Run hardened server
docker run -d --name hardened-server \
  --network hardened-net \
  -p 2222:2222 \
  -v hardened-logs:/var/log \
  hardened-server:v1 bash

# Run monitor
docker run -d --name monitor \
  --network hardened-net \
  -p 19999:19999 \
  -v hardened-logs:/monitored-logs:ro \
  netdata/netdata
```

## What I Learned
- Linux server hardening techniques
- SSH security configuration
- Intrusion detection and prevention
- Centralized logging architecture
- Docker networking and volumes
- Security monitoring with Netdata