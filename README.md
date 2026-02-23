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
Phase 2 ✅  Ansible Automation
Phase 3 ✅  SOC Home Lab (Loki + Grafana + Promtail + Suricata)
Phase 4 ⏳  Red Team Lab (Attack simulation on AWS)
```

---

## ✅ Phase 1 — Hardened Server & Monitoring

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
```

### Security Layers

| Layer | Tool | Protection |
|---|---|---|
| SSH Hardening | sshd_config | Custom port, no root, keys only |
| Brute Force Protection | Fail2ban | Bans IPs after 3 failed attempts |
| File Integrity Monitoring | inotifywait | Detects changes to critical files |
| Centralized Logging | rsyslog + Docker volume | All logs readable from monitor |
| Real-time Monitoring | Netdata | Live dashboard at port 19999 |
| CI/CD Validation | GitHub Actions | Auto-validates security controls on push |

### Attack Simulation Results

| Attack | Control | Result |
|---|---|---|
| Root SSH login | PermitRootLogin no | ❌ Blocked |
| Brute force (3 attempts) | Fail2ban | 🚫 IP Banned |
| Password auth attempt | PasswordAuthentication no | ❌ Rejected |
| Critical file modification | inotifywait | 🔔 Detected & Logged |

---

## ✅ Phase 2 — Ansible Automation

### What it does

One command rebuilds the entire hardened environment from zero:

```bash
ansible-playbook playbooks/site.yml
```

### Roles

```
ansible/
├── inventory/hosts.yml          # Target server inventory
├── ansible.cfg                  # Roles path + defaults
├── playbooks/
│   └── site.yml                 # Master playbook
└── roles/
    ├── ssh-hardening/           # Deploys hardened sshd_config
    ├── fail2ban/                # Installs + configures Fail2ban
    └── file-integrity/          # inotifywait file monitor
```

### Key Lessons from Phase 2

- **Never automate as root** — dedicated ansible user with scoped sudo
- **Idempotency** — changed=0 on second run = production ready
- **Deploy full config files** instead of patching line by line
- **Port changes break connectivity** — update inventory after SSH hardening

---

## ✅ Phase 3 — SOC Home Lab

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      hardened-net                               │
│                                                                  │
│  ┌─────────────────┐    ┌──────────┐    ┌────────────────────┐  │
│  │  ansible-target  │    │ promtail │    │       loki         │  │
│  │  SSH :2222       │───►│          │───►│  log aggregation   │  │
│  │  Fail2ban        │    │ watches  │    └────────────────────┘  │
│  │  inotifywait     │    │ auth.log │             │              │
│  └─────────────────┘    └──────────┘             ▼              │
│                                         ┌────────────────────┐  │
│  ┌─────────────────┐                    │      grafana        │  │
│  │    suricata      │                   │  SOC dashboard     │  │
│  │  48,716 rules    │                   │  port 3000         │  │
│  │  network IDS     │                   └────────────────────┘  │
│  └─────────────────┘                                            │
│  shared volume: hardened-logs                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Log Pipeline

```
ansible-target → /var/log/auth.log → promtail → loki → grafana
```

### SOC Stack

| Tool | Role | Port |
|---|---|---|
| Loki | Log aggregation | 3100 |
| Grafana | SOC dashboard | 3000 |
| Promtail | Log shipping agent | 9080 |
| Suricata | Network IDS (48,716 ET/Open rules) | — |

### Grafana Dashboard Queries

```
# Live log stream
{job="hardened-server"}

# Failed logins per minute
count_over_time({job="hardened-server"} |= "Failed" [1m])

# Fail2ban bans
{job="hardened-server"} |= "Ban"
```

### Architecture Decision — Suricata Network Tap

Suricata was deployed with 48,716 ET/Open rules loaded and successfully running on eth0. In Docker bridge networking, inter-container traffic is processed at the kernel bridge level — below the interface Suricata monitors.

**Production solution:** Suricata runs on the host network interface or a dedicated macvlan tap. This is planned for Phase 4 on AWS EC2 where full network control is available.

> Documenting this constraint demonstrates understanding of network architecture beyond surface-level configuration.

### How to Run Phase 3

```powershell
# Loki
docker run -d --name loki --network hardened-net -p 3100:3100 grafana/loki:latest

# Grafana
docker run -d --name grafana --network hardened-net -p 3000:3000 grafana/grafana:latest

# Promtail
docker run -d --name promtail \
  --network hardened-net \
  -v hardened-logs:/var/log/hardened:ro \
  -v ./promtail-config.yml:/etc/promtail/config.yml \
  grafana/promtail:latest

# Suricata
docker run -d --name suricata \
  --network hardened-net \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  -v hardened-logs:/var/log/suricata \
  jasonish/suricata:latest -i eth0

# Load rules
docker exec suricata suricata-update enable-source et/open
docker exec suricata suricata-update
```

---

## ⏳ Phase 4 — Red Team Lab (AWS)

### Why AWS

Local Docker networking limits full network traffic inspection. Phase 4 moves to AWS EC2 where:
- Full kernel network access for Suricata tap interface
- Terraform provisions everything reproducibly
- Kali Linux attacker with full capabilities
- MITRE ATT&CK simulation (T1021, T1046, T1190)
- All alerts visible in real-time on Grafana SOC dashboard

---

## 📁 Repository Structure

```
hardened-infra/
├── .github/workflows/ci.yml
├── hardened-server/
│   ├── Dockerfile
│   ├── sshd_config
│   ├── fail2ban-jail.local
│   └── scripts/start.sh
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/hosts.yml
│   ├── playbooks/site.yml
│   └── roles/
│       ├── ssh-hardening/
│       ├── fail2ban/
│       └── file-integrity/
├── promtail-config.yml
└── docs/
    ├── hardening-steps.md
    ├── attack-simulation.md
    └── soc-lab.md
```

---

## 📚 Documentation

- [Hardening Steps & Lessons Learned](docs/hardening-steps.md)
- [Attack Simulation Results](docs/attack-simulation.md)
- [SOC Lab Complete Guide](docs/soc-lab.md)

---

## 🧠 Key Lessons

1. **Containers ≠ VMs** — kernel modules behave differently
2. **Logs are everything** — Fail2ban is useless without log infrastructure
3. **Never automate as root** — dedicated service accounts with scoped sudo
4. **Idempotency matters** — changed=0 every time = production ready
5. **Network architecture is critical** — Docker bridge limits packet inspection
6. **Document the obstacles** — every wall hit proves real experience

---

## 🛠️ Tech Stack

`Docker` `Ubuntu 22.04` `Fail2ban` `Netdata` `rsyslog` `inotifywait` `GitHub Actions` `Ansible` `Suricata` `Loki` `Grafana` `Promtail`

---

## 👤 Author

**Khalil Ghiati** — Infrastructure & Security Engineer

[![GitHub](https://img.shields.io/badge/GitHub-Khalil--secure-181717?logo=github)](https://github.com/Khalil-secure)
[![Portfolio](https://img.shields.io/badge/Portfolio-khalilghiati.dev-0F4C81)](https://khalilghiati.dev)
