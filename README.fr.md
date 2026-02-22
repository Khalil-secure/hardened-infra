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
Phase 3 ✅  SOC Home Lab (ELK + Suricata)
Phase 4 ⏳  Red Team Lab (Simulation d'attaques)
```

---

## ✅ Phase 1 — Serveur Durci & Monitoring (Terminée)

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
                      172.20.0.0/24
```

### Couches de Sécurité Implémentées

| Couche | Outil | Rôle |
|---|---|---|
| Durcissement SSH | sshd_config | Port custom, pas de root, clés uniquement, limites strictes |
| Protection Brute Force | Fail2ban | Bannissement IP après 3 tentatives échouées |
| Surveillance Intégrité | inotifywait | Détecte toute modification sur les fichiers critiques |
| Logs Centralisés | rsyslog + volume Docker | Tous les logs lisibles depuis le conteneur monitor |
| Monitoring Temps Réel | Netdata | Dashboard live sur port 19999 |
| Validation CI/CD | GitHub Actions | Valide automatiquement tous les contrôles de sécurité |

### Configuration SSH Durcie

```
Port 2222                    # Évite les scanners automatisés
PermitRootLogin no           # Root ne peut pas se connecter en SSH
MaxAuthTries 3               # Coupe les attaques brute force
LoginGraceTime 30            # Pas d'attaques lentes ou inactives
PasswordAuthentication no    # Clés uniquement
AllowTcpForwarding no        # Pas de tunneling de trafic
X11Forwarding no             # Pas de tunneling GUI
LogLevel VERBOSE             # Logs complets pour forensique
```

### Résultats de Simulation d'Attaques

| Attaque | Contrôle | Résultat |
|---|---|---|
| Connexion SSH en root | PermitRootLogin no | ❌ Bloqué |
| Brute force (3 tentatives) | Fail2ban | 🚫 IP Bannie |
| Tentative auth par mot de passe | PasswordAuthentication no | ❌ Refusé |
| Modification fichier critique | inotifywait | 🔔 Détecté & Journalisé |
| Visibilité logs depuis monitor | Volume Docker partagé | ✅ Visibilité complète |

### Comment Lancer la Phase 1

```bash
# Créer le réseau et le volume
docker network create hardened-net
docker volume create hardened-logs

# Lancer le serveur durci
docker run -d --name hardened-server \
  --network hardened-net \
  -p 2222:2222 \
  -v hardened-logs:/var/log \
  hardened-server:v1 bash

# Lancer le monitor
docker run -d --name monitor \
  --network hardened-net \
  -p 19999:19999 \
  -v hardened-logs:/monitored-logs:ro \
  netdata/netdata

# Accéder au dashboard Netdata
open http://localhost:19999
```

---

## 🔄 Phase 2 — Automatisation Ansible (En cours)

### Objectif
Éliminer toute configuration manuelle. Une seule commande reconstruit l'environnement durci complet depuis zéro.

### Playbooks Prévus

```
ansible/
├── inventory/
│   └── hosts.yml              # Inventaire des conteneurs
├── playbooks/
│   ├── harden.yml             # Séquence de durcissement complète
│   ├── deploy-fail2ban.yml    # Configuration Fail2ban
│   ├── deploy-monitoring.yml  # Netdata + envoi de logs
│   └── site.yml               # Playbook maître (lance tout)
└── roles/
    ├── ssh-hardening/         # Rôle configuration SSH
    ├── fail2ban/              # Rôle IDS
    └── file-integrity/        # Rôle inotifywait
```

### Commande Cible

```bash
# Toute l'infrastructure durcie en une seule commande
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

---

## ⏳ Phase 3 — SOC Home Lab

### Objectif
Ajouter une stack SOC complète par-dessus l'infrastructure durcie — détection de menaces en temps réel, corrélation d'alertes et couverture MITRE ATT&CK.

### Architecture Prévue

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  hardened-server │    │   suricata-ids   │    │   elk-stack      │
│  (Phase 1)       │───►│  IDS/IPS Réseau  │───►│  Elasticsearch   │
│                  │    │  Règles MITRE    │    │  Logstash        │
│                  │    │  ATT&CK          │    │  Kibana          │
└──────────────────┘    └──────────────────┘    └──────────────────┘
                                                         │
                                               ┌──────────────────┐
                                               │  moteur-alertes  │
                                               │  Threat hunting  │
                                               │  Dashboard SOC   │
                                               └──────────────────┘
```

### Stack Prévu

| Outil | Rôle |
|---|---|
| Suricata | IDS/IPS réseau avec règles MITRE ATT&CK |
| Elasticsearch | Stockage et indexation des logs |
| Logstash | Pipeline d'ingestion et de parsing |
| Kibana | Dashboard SOC et visualisation |
| Règles custom | Mappées sur le framework MITRE ATT&CK |

---

## ⏳ Phase 4 — Red Team Lab

### Objectif
Construire un environnement isolé de simulation d'attaques pour tester les défenses, comprendre les techniques des attaquants et générer de vraies alertes dans le SOC.

### Architecture Prévue

```
┌─────────────────────────────────────────────────────┐
│              RÉSEAU DE LAB ISOLÉ                     │
│                                                      │
│  ┌─────────────┐         ┌─────────────────────┐    │
│  │  kali-linux │────────►│   hardened-server   │    │
│  │  attaquant  │         │  (cible/défenseur)  │    │
│  └─────────────┘         └─────────────────────┘    │
│         │                          │                 │
│         │              ┌───────────────────────┐     │
│         └─────────────►│     Stack SOC         │     │
│                        │  (Phase 3 — monitor)  │     │
│                        └───────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

### Scénarios d'Attaques Prévus

- Reconnaissance — scan nmap, énumération de services
- Brute force — attaques SSH, déclenchement Fail2ban
- Tentatives d'élévation de privilèges — surveillées par inotifywait
- Simulation de mouvement latéral — pivoting réseau
- Toutes les attaques visibles en temps réel sur le dashboard SOC

> ⚠️ Toutes les attaques sont réalisées exclusivement dans cet environnement de lab isolé, sur une infrastructure que je possède et contrôle.

---

## 📁 Structure du Dépôt

```
hardened-infra/
├── .github/
│   └── workflows/
│       └── ci.yml                  # Pipeline GitHub Actions
├── hardened-server/
│   ├── Dockerfile                  # Image Ubuntu durcie
│   ├── sshd_config                 # Configuration SSH durcie
│   ├── fail2ban-jail.local         # Configuration Fail2ban
│   └── scripts/
│       └── start.sh                # Script de démarrage conteneur
├── docs/
│   ├── hardening-steps.md          # Étapes détaillées avec obstacles réels
│   └── attack-simulation.md       # Résultats des tests d'attaques live
└── README.md
```

---

## 📚 Documentation

- [Étapes de Durcissement & Leçons Apprises](docs/hardening-steps.md) — chaque obstacle rencontré et comment il a été résolu
- [Résultats de Simulation d'Attaques](docs/attack-simulation.md) — tests brute force live et réponses de l'IDS

---

## 🧠 Leçons Clés Apprises

1. **Les conteneurs ne sont pas des VMs** — auditd, systemd, les modules kernel se comportent différemment. Connaître son environnement est essentiel.
2. **Les logs sont tout** — Fail2ban est inutile sans une infrastructure de logs fonctionnelle.
3. **Toujours vérifier avec netstat** — ne pas supposer qu'un service est sécurisé, vérifier ce qui écoute réellement.
4. **Tester le durcissement** — essayer activement de pénétrer et vérifier que chaque contrôle fonctionne.
5. **Les obstacles sont de la documentation** — chaque mur rencontré prouve une expérience pratique réelle.

---

## 🛠️ Stack Technique

`Docker` `Ubuntu 22.04` `Fail2ban` `Netdata` `rsyslog` `inotifywait` `GitHub Actions` `Ansible (Phase 2)` `Suricata (Phase 3)` `ELK Stack (Phase 3)` `Kali Linux (Phase 4)`

---

## 👤 Auteur

**Khalil Ghiati** — Ingénieur Infrastructure & Sécurité

[![GitHub](https://img.shields.io/badge/GitHub-Khalil--secure-181717?logo=github)](https://github.com/Khalil-secure)
[![Portfolio](https://img.shields.io/badge/Portfolio-khalilghiati.dev-0F4C81)](https://portfolio-khalil-secure.vercel.app/)
