> 🇫🇷 [Version française disponible ici](README.fr.md)

# 🔒 Hardened Infrastructure Lab

> A hands-on security engineering project — building, breaking, and documenting a production-grade hardened environment from scratch.

![CI/CD](https://github.com/Khalil-secure/hardened-infra/actions/workflows/ci.yml/badge.svg)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu_22.04-E95420?logo=ubuntu&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📌 Project Vision

This project is a progressive security lab built layer by layer — starting from a hardened Linux server, evolving into a full SOC environment, and ultimately into a complete Red Team / Blue Team infrastructure.

Every step is documented with real obstacles hit and how they were solved. This is not a tutorial follow-along — it's built from scratch, tested live, and pushed to its limits.

---

## 🗺️ Roadmap

```
Phase 1 ✅  Hardened Server + Monitoring
Phase 2 🔄  Ansible Automation
Phase 3 ⏳  SOC Home Lab (ELK + Suricata)
Phase 4 ⏳  Red Team Lab (Attack simulation)
```

---

## ✅ Phase 1 — Hardened Server & Monitoring (Complete)

### Architecture

```
┌─────────────────────────┐         ┌──────────────────────────┐
│     hardened-server     │         │         monitor          │
│  ─────────────────────  │         │  ──────────────────────  │
│  Ubuntu 22.04           │◄───────►│  Netdata (port 19999)    │
│  SSH hardened :2222     │         │  Reads logs in real-time │
│  Fail2ban (IDS)         │         │  auth.log                │
│  File integrity monitor │         │  fail2ban.log            │
│  rsyslog                │         │  file-monitor.log        │
└─────────────────────────┘         └──────────────────────────┘
           │                                    │
           └──────────── hardened-net ──────────┘
                    (private bridge network)
                      172.20.0.0/24
```

### Security Layers Implemented

| Layer | Tool | What it does |
|---|---|---|
| SSH Hardening | sshd_config | Custom port, no root, keys only, strict limits |
| Brute Force Protection | Fail2ban | Bans IPs after 3 failed attempts |
| File Integrity Monitoring | inotifywait | Detects any change to critical files |
| Centralized Logging | rsyslog + Docker volume | All logs readable from monitor container |
| Real-time Monitoring | Netdata | Live dashboard at port 19999 |
| CI/CD Validation | GitHub Actions | Auto-validates all security controls on push |

### SSH Hardening Config

```
Port 2222                    # Avoids automated bot scanners
PermitRootLogin no           # Root cannot SSH in
MaxAuthTries 3               # Cuts off brute force
LoginGraceTime 30            # No slow/idle attacks
PasswordAuthentication no    # Keys only
AllowTcpForwarding no        # No traffic tunneling
X11Forwarding no             # No GUI tunneling
LogLevel VERBOSE             # Full forensic logging
```

### Attack Simulation Results

| Attack | Control | Result |
|---|---|---|
| Root SSH login | PermitRootLogin no | ❌ Blocked |
| Brute force (3 attempts) | Fail2ban | 🚫 IP Banned |
| Password auth attempt | PasswordAuthentication no | ❌ Rejected |
| Critical file modification | inotifywait | 🔔 Detected & Logged |
| Log visibility from monitor | Shared Docker volume | ✅ Full visibility |

### How to Run Phase 1

```bash
# Create network and volume
docker network create hardened-net
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

# Access Netdata dashboard
open http://localhost:19999
```

---

## 🔄 Phase 2 — Ansible Automation (In Progress)

### Goal
Eliminate all manual configuration. One command rebuilds the entire hardened environment from zero.

### Planned Playbooks

```
ansible/
├── inventory/
│   └── hosts.yml              # Container inventory
├── playbooks/
│   ├── harden.yml             # Full hardening sequence
│   ├── deploy-fail2ban.yml    # Fail2ban setup and config
│   ├── deploy-monitoring.yml  # Netdata + log shipping
│   └── site.yml               # Master playbook (runs all)
└── roles/
    ├── ssh-hardening/         # SSH config role
    ├── fail2ban/              # IDS role
    └── file-integrity/        # inotifywait role
```

### Target Command

```bash
# Entire hardened infrastructure in one command
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

---

## ⏳ Phase 3 — SOC Home Lab

### Goal
Add a full Security Operations Center stack on top of the hardened infrastructure — real-time threat detection, alert correlation, and MITRE ATT&CK coverage.

### Planned Architecture

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  hardened-server │    │    suricata-ids   │    │   elk-stack      │
│  (Phase 1)       │───►│  Network IDS/IPS  │───►│  Elasticsearch   │
│                  │    │  MITRE ATT&CK     │    │  Logstash        │
│                  │    │  rules            │    │  Kibana          │
└──────────────────┘    └──────────────────┘    └──────────────────┘
                                                         │
                                               ┌──────────────────┐
                                               │   alert-engine   │
                                               │  Threat hunting  │
                                               │  SOC dashboard   │
                                               └──────────────────┘
```

### Planned Stack

| Tool | Role |
|---|---|
| Suricata | Network IDS/IPS with MITRE ATT&CK rules |
| Elasticsearch | Log storage and indexing |
| Logstash | Log ingestion and parsing pipeline |
| Kibana | SOC dashboard and visualization |
| Custom rules | Mapped to MITRE ATT&CK framework |

---

## ⏳ Phase 4 — Red Team Lab

### Goal
Build an isolated attack simulation environment to test defenses, understand attacker techniques, and generate real alerts in the SOC.

### Planned Architecture

```
┌─────────────────────────────────────────────────────┐
│                  ISOLATED LAB NETWORK                │
│                                                      │
│  ┌─────────────┐         ┌─────────────────────┐    │
│  │  kali-linux │────────►│   hardened-server   │    │
│  │  attacker   │         │   (target/defender) │    │
│  └─────────────┘         └─────────────────────┘    │
│         │                          │                 │
│         │              ┌───────────────────────┐     │
│         └─────────────►│      SOC Stack        │     │
│                        │   (Phase 3 — monitor) │     │
│                        └───────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

### Planned Attack Scenarios

- Reconnaissance — nmap scanning, service enumeration
- Brute force — SSH attacks, triggering Fail2ban
- Privilege escalation attempts — monitored by file integrity
- Lateral movement simulation — network pivoting
- All attacks visible in real-time on SOC dashboard

> ⚠️ All attacks are performed exclusively in this isolated lab environment on infrastructure I own and control.

---

## 📁 Repository Structure

```
hardened-infra/
├── .github/
│   └── workflows/
│       └── ci.yml              # GitHub Actions pipeline
├── hardened-server/
│   ├── Dockerfile              # Hardened Ubuntu image
│   ├── sshd_config             # Hardened SSH config
│   ├── fail2ban-jail.local     # Fail2ban configuration
│   └── scripts/
│       └── start.sh            # Container startup script
├── docs/
│   ├── hardening-steps.md      # Step-by-step with real obstacles
│   └── attack-simulation.md   # Live attack test results
└── README.md
```

---

## 📚 Documentation

- [Hardening Steps & Lessons Learned](docs/hardening-steps.md) — every wall hit and how it was solved
- [Attack Simulation Results](docs/attack-simulation.md) — live brute force tests and IDS responses

---

## 🧠 Key Lessons Learned

1. **Containers are not VMs** — auditd, systemd, kernel modules behave differently. Know your environment.
2. **Logs are everything** — Fail2ban is useless without working log infrastructure.
3. **Always verify with netstat** — don't assume a service is secure, check what's actually listening.
4. **Test your hardening** — actively try to break in and verify each control works.
5. **Obstacles are documentation** — every wall hit is evidence of real hands-on experience.

---

## 🛠️ Tech Stack

`Docker` `Ubuntu 22.04` `Fail2ban` `Netdata` `rsyslog` `inotifywait` `GitHub Actions` `Ansible (Phase 2)` `Suricata (Phase 3)` `ELK Stack (Phase 3)` `Kali Linux (Phase 4)`

---

## 👤 Author

**Khalil Ghiati** — Infrastructure & Security Engineer

[![GitHub](https://img.shields.io/badge/GitHub-Khalil--secure-181717?logo=github)](https://github.com/Khalil-secure)
[![Portfolio](https://img.shields.io/badge/Portfolio-khalilghiati.dev-0F4C81)](https://portfolio-khalil-secure.vercel.app/)