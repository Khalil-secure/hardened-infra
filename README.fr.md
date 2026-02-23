> 🇬🇧 [English version available here](README.md)

# 🔒 Laboratoire d'Infrastructure Sécurisée

> Un projet d'ingénierie sécurité construit de zéro — durcissement, tests d'intrusion, et documentation complète d'un environnement de production sécurisé.

![CI/CD](https://github.com/Khalil-secure/hardened-infra/actions/workflows/ci.yml/badge.svg)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu_22.04-E95420?logo=ubuntu&logoColor=white)
![License](https://img.shields.io/badge/licence-MIT-green)

---

## 📌 Vision du Projet

Ce projet est un laboratoire de sécurité progressif, construit couche par couche — en partant d'un serveur Linux durci, pour évoluer vers un environnement SOC complet, et finalement une infrastructure Red Team / Blue Team complète.

Chaque étape est documentée avec les obstacles réels rencontrés et la façon dont ils ont été résolus. Ce n'est pas un tutoriel suivi pas à pas — c'est construit from scratch, testé en conditions réelles, et poussé dans ses retranchements.

---

## 🗺️ Feuille de Route

```
Phase 1 ✅  Serveur Durci + Monitoring
Phase 2 ✅  Automatisation Ansible
Phase 3 ✅  SOC Home Lab (Loki + Grafana + Promtail + Suricata)
Phase 4 ⏳  Red Team Lab (Simulation d'attaques sur AWS)
```

---

## ✅ Phase 1 — Serveur Durci & Monitoring

### Architecture

```
┌─────────────────────────┐         ┌──────────────────────────┐
│     hardened-server     │         │         monitor          │
│  ─────────────────────  │         │  ──────────────────────  │
│  Ubuntu 22.04           │◄───────►│  Netdata (port 19999)    │
│  SSH durci :2222        │         │  Lecture logs temps réel │
│  Fail2ban (IDS)         │         │  auth.log                │
│  Surveillance fichiers  │         │  fail2ban.log            │
│  rsyslog                │         │  file-monitor.log        │
└─────────────────────────┘         └──────────────────────────┘
           │                                    │
           └──────────── hardened-net ──────────┘
                    (réseau bridge privé)
```

### Couches de Sécurité

| Couche | Outil | Protection |
|---|---|---|
| Durcissement SSH | sshd_config | Port custom, pas de root, clés uniquement |
| Protection Brute Force | Fail2ban | Bannissement IP après 3 tentatives échouées |
| Surveillance Intégrité | inotifywait | Détecte les modifications sur les fichiers critiques |
| Logs Centralisés | rsyslog + volume Docker | Tous les logs lisibles depuis le monitor |
| Monitoring Temps Réel | Netdata | Dashboard live sur port 19999 |
| Validation CI/CD | GitHub Actions | Valide automatiquement les contrôles de sécurité |

### Résultats de Simulation d'Attaques

| Attaque | Contrôle | Résultat |
|---|---|---|
| Connexion SSH en root | PermitRootLogin no | ❌ Bloqué |
| Brute force (3 tentatives) | Fail2ban | 🚫 IP Bannie |
| Tentative auth par mot de passe | PasswordAuthentication no | ❌ Refusé |
| Modification fichier critique | inotifywait | 🔔 Détecté & Journalisé |

---

## ✅ Phase 2 — Automatisation Ansible

### Ce que ça fait

Une seule commande reconstruit l'environnement durci complet depuis zéro :

```bash
ansible-playbook playbooks/site.yml
```

### Rôles

```
ansible/
├── inventory/hosts.yml          # Inventaire du serveur cible
├── ansible.cfg                  # Chemin des rôles + paramètres par défaut
├── playbooks/
│   └── site.yml                 # Playbook maître
└── roles/
    ├── ssh-hardening/           # Déploie sshd_config durci
    ├── fail2ban/                # Installe + configure Fail2ban
    └── file-integrity/          # Surveillance inotifywait
```

### Leçons Clés de la Phase 2

- **Ne jamais automatiser en root** — user `ansible` dédié avec sudo scopé
- **Idempotence** — changed=0 à la deuxième exécution = prêt pour la production
- **Déployer des fichiers de config complets** plutôt que de patcher ligne par ligne
- **Les changements de port cassent la connectivité** — mettre à jour l'inventaire après durcissement SSH

---

## ✅ Phase 3 — SOC Home Lab

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      hardened-net                               │
│                                                                  │
│  ┌─────────────────┐    ┌──────────┐    ┌────────────────────┐  │
│  │  ansible-target  │    │ promtail │    │       loki         │  │
│  │  SSH :2222       │───►│          │───►│  agrégation logs   │  │
│  │  Fail2ban        │    │ surveille│    └────────────────────┘  │
│  │  inotifywait     │    │ auth.log │             │              │
│  └─────────────────┘    └──────────┘             ▼              │
│                                         ┌────────────────────┐  │
│  ┌─────────────────┐                    │      grafana        │  │
│  │    suricata      │                   │  Dashboard SOC     │  │
│  │  48 716 règles   │                   │  port 3000         │  │
│  │  IDS réseau      │                   └────────────────────┘  │
│  └─────────────────┘                                            │
│  volume partagé: hardened-logs                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Pipeline de Logs

```
ansible-target → /var/log/auth.log → promtail → loki → grafana
```

### Stack SOC

| Outil | Rôle | Port |
|---|---|---|
| Loki | Agrégation de logs | 3100 |
| Grafana | Dashboard SOC | 3000 |
| Promtail | Agent d'envoi de logs | 9080 |
| Suricata | IDS réseau (48 716 règles ET/Open) | — |

### Requêtes Dashboard Grafana

```
# Flux de logs en direct
{job="hardened-server"}

# Connexions échouées par minute
count_over_time({job="hardened-server"} |= "Failed" [1m])

# Bannissements Fail2ban
{job="hardened-server"} |= "Ban"
```

### Décision d'Architecture — Tap Réseau Suricata

Suricata a été déployé avec 48 716 règles ET/Open chargées et fonctionne correctement sur eth0. Dans un réseau bridge Docker, le trafic inter-conteneurs est traité au niveau du kernel bridge Linux — en dessous de l'interface surveillée par Suricata.

**Solution en production :** Suricata tourne sur l'interface réseau de l'hôte ou sur un tap macvlan dédié. Prévu pour la Phase 4 sur AWS EC2 où le contrôle réseau complet est disponible.

> Documenter cette contrainte démontre une compréhension de l'architecture réseau au-delà de la configuration superficielle.

### Comment Lancer la Phase 3

```powershell
# Loki
docker run -d --name loki --network hardened-net -p 3100:3100 grafana/loki:latest

# Grafana
docker run -d --name grafana --network hardened-net -p 3000:3000 grafana/grafana:latest

# Promtail
docker run -d --name promtail `
  --network hardened-net `
  -v hardened-logs:/var/log/hardened:ro `
  -v ./promtail-config.yml:/etc/promtail/config.yml `
  grafana/promtail:latest

# Suricata
docker run -d --name suricata `
  --network hardened-net `
  --cap-add NET_ADMIN --cap-add NET_RAW `
  -v hardened-logs:/var/log/suricata `
  jasonish/suricata:latest -i eth0

# Charger les règles
docker exec suricata suricata-update enable-source et/open
docker exec suricata suricata-update
```

---

## ⏳ Phase 4 — Red Team Lab (AWS)

### Pourquoi AWS

Le réseau Docker local limite l'inspection complète du trafic réseau. La Phase 4 passe sur AWS EC2 où :
- Accès complet au kernel pour l'interface tap Suricata
- Terraform provisionne tout de manière reproductible
- Kali Linux attaquant avec capacités complètes
- Simulation MITRE ATT&CK (T1021, T1046, T1190)
- Toutes les alertes visibles en temps réel sur le dashboard Grafana

---

## 📁 Structure du Dépôt

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
    ├── soc-lab.md
    └── soc-lab-fr.md
```

---

## 📚 Documentation

- [Étapes de Durcissement & Leçons Apprises](docs/hardening-steps.md)
- [Résultats de Simulation d'Attaques](docs/attack-simulation.md)
- [Guide Complet SOC Lab](docs/soc-lab-fr.md)

---

## 🧠 Leçons Clés

1. **Les conteneurs ≠ VMs** — les modules kernel se comportent différemment
2. **Les logs sont tout** — Fail2ban est inutile sans infrastructure de logs
3. **Ne jamais automatiser en root** — comptes de service dédiés avec sudo scopé
4. **L'idempotence est essentielle** — changed=0 à chaque fois = prêt pour la production
5. **L'architecture réseau est critique** — le bridge Docker limite l'inspection de paquets
6. **Documenter les obstacles** — chaque mur rencontré prouve une expérience réelle

---

## 🛠️ Stack Technique

`Docker` `Ubuntu 22.04` `Fail2ban` `Netdata` `rsyslog` `inotifywait` `GitHub Actions` `Ansible` `Suricata` `Loki` `Grafana` `Promtail`

---

## 👤 Auteur

**Khalil Ghiati** — Ingénieur Infrastructure & Sécurité

[![GitHub](https://img.shields.io/badge/GitHub-Khalil--secure-181717?logo=github)](https://github.com/Khalil-secure)
[![Portfolio](https://img.shields.io/badge/Portfolio-khalilghiati.dev-0F4C81)](https://khalilghiati.dev)