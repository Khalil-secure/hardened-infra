# Hardening Steps & Lessons Learned

A real documentation of the hardening process, including every obstacle 
hit and how it was resolved. This is not a clean tutorial — it's what 
actually happened.

---

## Environment
- Windows host machine
- Docker Desktop
- Base image: Ubuntu 22.04
- Container name: hardened-server

---

## Step 1 — Baseline Assessment

Started with a fresh Ubuntu 22.04 container and ran `netstat -tlnp`.

**Result:** Zero open ports, zero running services.

> This is the baseline. Every port we open from here is a conscious 
> decision we are responsible for securing.

---

## Step 2 — SSH Installation & Default State

Installed openssh-server and started it. Ran `netstat -tlnp` again.

**Result:**
```
0.0.0.0:22    LISTEN
:::22         LISTEN
```

Port 22 wide open on every interface, IPv4 and IPv6.
No restrictions, no limits, no bans. Default = dangerous.

---

## Step 3 — SSH Hardening

Edited `/etc/ssh/sshd_config` line by line:

| Setting | Before | After | Reason |
|---|---|---|---|
| Port | 22 | 2222 | Avoids automated bot scanners |
| PermitRootLogin | yes | no | Root cannot SSH in |
| MaxAuthTries | 6 | 3 | Cuts off brute force faster |
| LoginGraceTime | 120 | 30 | Kills slow/idle auth attempts |
| PasswordAuthentication | yes | no | Keys only, no password attacks |
| X11Forwarding | yes | no | No GUI tunneling |
| AllowTcpForwarding | yes | no | No traffic tunneling |
| LogLevel | INFO | VERBOSE | Full logging for forensics |

**Wall hit:** Added `X11Forwarding no` at the top of the file but the 
default `X11Forwarding yes` lower down was overriding it. Config files 
are read top to bottom but existing values can conflict.

**Fix:** Found and changed the existing line instead of adding a new one.

---

## Step 4 — Non-Root User & Key Authentication

Created unprivileged user `secuser`:
```bash
useradd -m -s /bin/bash secuser
passwd secuser
```

Generated ED25519 SSH key pair:
```bash
ssh-keygen -t ed25519 -C "secuser@hardened-server"
```

Set up authorized_keys and tested key-based login successfully.
Then disabled password authentication entirely.

**Result:** SSH now only accepts key-based authentication. 
Password brute force is impossible.

---

## Step 5 — Fail2ban Setup

**Wall 1: No auth.log**
Fail2ban couldn't start because `/var/log/auth.log` didn't exist.
Docker containers don't create log files by default.

**Fix:** Manually created the file:
```bash
touch /var/log/auth.log
```

**Wall 2: rsyslog wouldn't start**
`service rsyslog start` returned `unrecognized service`.
Docker containers don't run systemd so standard service management fails.

**Fix:** Started rsyslog directly:
```bash
rsyslogd
```

**Wall 3: rsyslog permission errors**
Even after starting, rsyslog couldn't write to log files.
Error: `action suspended - operation not permitted`

**Fix:** Fixed log file permissions:
```bash
chmod 666 /var/log/auth.log
chmod 666 /var/log/syslog
```

**Wall 4: Fail2ban ignoring attacks**
After triggering 3 failed SSH attempts, Fail2ban showed 0 bans.
Checked the live log and found:
```
[sshd] Ignore ::1 by ignoreself rule
```
Fail2ban has a built-in rule that prevents banning the machine's own IP.
Since we were testing from localhost (::1), every attack was ignored.

**Fix:** Disabled the ignoreself rule in jail.local:
```ini
ignoreself = false
```

**Result:** 
```
[sshd] Found ::1
[sshd] Found ::1
[sshd] Found ::1
[sshd] Ban ::1
```
Brute force detected and banned in real time.

---

## Step 6 — File Integrity Monitoring

Attempted to use `auditd` for file integrity monitoring.

**Wall: auditd blocked by Docker**
Even with `--privileged` flag, Docker on Windows blocks audit syscalls.
The Windows Docker Desktop VM kernel doesn't expose the audit subsystem.

```bash
auditctl -e 1
# Error sending enable request (Operation not permitted)
```

**Fix:** Used `inotifywait` instead — a filesystem-level monitoring tool 
that doesn't require kernel audit access:

```bash
inotifywait -m -e modify,attrib,move,create,delete \
  /etc/passwd \
  /etc/shadow \
  /etc/ssh/sshd_config \
  >> /var/log/file-monitor.log 2>&1 &
```

**Result:** Any modification to critical files is instantly logged:
```
/etc/passwd MODIFY
/etc/ssh/sshd_config MODIFY
```

> Note: In production on bare metal or a VM, auditd would be the 
> preferred tool as it operates at the kernel level and is harder to 
> bypass than filesystem-level monitoring.

---

## Step 7 — Centralized Log Management

**Wall: --volumes-from mounted wrong container**
Used `--volumes-from hardened-server` but it mounted logs from a 
previously named container (hardened-v2) instead.

**Fix:** Used a named Docker volume instead:
```bash
docker volume create hardened-logs
```
Mounted to hardened-server as read-write, to monitor as read-only.

**Result:** Monitor container reads live logs from hardened-server:
- `/monitored-logs/auth.log` — SSH attempts
- `/monitored-logs/fail2ban.log` — bans and detections  
- `/monitored-logs/file-monitor.log` — file integrity events

---

## Key Lessons

1. **Containers are not VMs** — systemd, auditd, kernel modules behave 
   differently. Know your environment before assuming tools will work.

2. **Always verify with netstat** — don't assume a service is secure, 
   check what's actually listening.

3. **Logs are everything** — Fail2ban is useless without logs. 
   Getting logging working was the hardest part.

4. **Test your hardening** — we didn't just configure, we actively 
   tried to break in and verified each control worked.

5. **Obstacles are documentation** — every wall hit is evidence of 
   real hands-on experience, not just following a guide.
```