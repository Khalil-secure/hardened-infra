# SOC Lab — Documentation Complète

Documentation complète du laboratoire SOC construit sur l'infrastructure durcie.
Chaque étape est reproductible depuis zéro en suivant ce guide.

---

## Architecture Complète

```
┌─────────────────────────────────────────────────────────────────┐
│                      hardened-net (172.18.0.0/24)               │
│                                                                  │
│  ┌─────────────────┐    ┌──────────┐    ┌────────────────────┐  │
│  │  ansible-target  │    │ promtail │    │       loki         │  │
│  │  172.18.0.2      │───►│          │───►│  172.18.0.x:3100   │  │
│  │  SSH :2222       │    │ watches  │    │  log aggregation   │  │
│  │  Fail2ban        │    │ auth.log │    └────────────────────┘  │
│  │  inotifywait     │    └──────────┘             │              │
│  └─────────────────┘                              ▼              │
│                                         ┌────────────────────┐  │
│  ┌─────────────────┐                    │      grafana        │  │
│  │ ansible-control  │                   │  172.18.0.x:3000   │  │
│  │  runs playbooks  │                   │  SOC dashboard     │  │
│  └─────────────────┘                    └────────────────────┘  │
│                                                                  │
│  shared volume: hardened-logs (/var/log)                        │
└─────────────────────────────────────────────────────────────────┘
```

### Log Pipeline

```
ansible-target
  └── /var/log/auth.log (SSH events, brute force, bans)
  └── /var/log/fail2ban.log (Fail2ban bans)
  └── /var/log/file-monitor.log (file integrity events)
        │
        │ (shared via hardened-logs Docker volume)
        ▼
    promtail
        │ ships logs to
        ▼
      loki (log aggregation)
        │ queried by
        ▼
    grafana (SOC dashboard at http://localhost:3000)
```

---

## Prérequis

- Docker Desktop installé et en cours d'exécution
- Au moins 2GB de RAM disponible pour Docker
- Réseau hardened-net créé
- Volume hardened-logs créé

---

## Reproduction depuis Zéro

### Étape 1 — Créer le réseau et le volume partagé

```powershell
docker network create hardened-net
docker volume create hardened-logs
```

---

### Étape 2 — Lancer le conteneur cible (ansible-target)

```powershell
docker run -d --name ansible-target `
  --network hardened-net `
  -v hardened-logs:/var/log `
  ubuntu:22.04 sleep infinity
```

Vérifier qu'il tourne :

```powershell
docker ps | findstr ansible-target
```

---

### Étape 3 — Installer SSH sur ansible-target

```powershell
docker exec ansible-target bash -c "
  apt-get update && apt-get install -y openssh-server sudo &&
  mkdir -p /run/sshd &&
  service ssh start
"
```

---

### Étape 4 — Lancer le conteneur de contrôle Ansible

```powershell
docker run -it --name ansible-control `
  --network hardened-net `
  ubuntu:22.04 bash
```

À l'intérieur du conteneur :

```bash
apt-get update && apt-get install -y ansible python3 openssh-client nano
```

---

### Étape 5 — Configurer l'accès SSH entre control et target

Sur ansible-control :

```bash
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
cat /root/.ssh/id_ed25519.pub
```

Copier la clé publique, puis sur ansible-target (depuis PowerShell) :

```powershell
docker exec ansible-target bash -c "
  useradd -m -s /bin/bash ansible &&
  mkdir -p /home/ansible/.ssh &&
  echo 'COLLER_LA_CLE_ICI' > /home/ansible/.ssh/authorized_keys &&
  chown -R ansible:ansible /home/ansible/.ssh &&
  chmod 700 /home/ansible/.ssh &&
  chmod 600 /home/ansible/.ssh/authorized_keys &&
  echo 'ansible ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
"
```

Tester la connexion :

```bash
ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no -p 22 ansible@172.18.0.2
```

---

### Étape 6 — Créer la structure Ansible

Sur ansible-control :

```bash
mkdir -p /ansible/{inventory,playbooks,roles/{ssh-hardening,fail2ban,file-integrity}/{tasks,files,handlers}}
cd /ansible
```

Créer ansible.cfg :

```bash
cat > /ansible/ansible.cfg << 'EOF'
[defaults]
roles_path = /ansible/roles
inventory = /ansible/inventory/hosts.yml
EOF
```

Créer l'inventaire :

```bash
cat > /ansible/inventory/hosts.yml << 'EOF'
all:
  hosts:
    hardened-server:
      ansible_host: 172.18.0.2
      ansible_user: ansible
      ansible_port: 22
      ansible_ssh_private_key_file: /root/.ssh/id_ed25519
      ansible_become: yes
      ansible_become_method: sudo
      ansible_ssh_extra_args: '-o StrictHostKeyChecking=no'
EOF
```

Tester :

```bash
ansible all -i /ansible/inventory/hosts.yml -m ping
```

Résultat attendu : `hardened-server | SUCCESS => pong`

---

### Étape 7 — Rôle SSH Hardening

```bash
cat > /ansible/roles/ssh-hardening/files/sshd_config << 'EOF'
Port 2222
AddressFamily any
ListenAddress 0.0.0.0
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
AllowTcpForwarding no
PrintMotd no
UsePAM yes
LogLevel VERBOSE
SyslogFacility AUTH
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
```

```bash
cat > /ansible/roles/ssh-hardening/tasks/main.yml << 'EOF'
---
- name: Install OpenSSH server
  apt:
    name: openssh-server
    state: present
    update_cache: yes

- name: Deploy hardened sshd_config
  copy:
    src: sshd_config
    dest: /etc/ssh/sshd_config
    owner: root
    group: root
    mode: '0644'
    backup: yes
  notify: restart ssh

- name: Ensure /run/sshd exists
  file:
    path: /run/sshd
    state: directory
    mode: '0755'
EOF
```

```bash
cat > /ansible/roles/ssh-hardening/handlers/main.yml << 'EOF'
---
- name: restart ssh
  service:
    name: ssh
    state: restarted
EOF
```

> ⚠️ Après l'exécution du rôle SSH, mettre à jour l'inventaire avec `ansible_port: 2222`

---

### Étape 8 — Rôle Fail2ban

```bash
cat > /ansible/roles/fail2ban/files/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
ignoreself = false

[sshd]
enabled   = true
port      = 2222
logpath   = /var/log/auth.log
maxretry  = 3
banaction = dummy
EOF
```

```bash
cat > /ansible/roles/fail2ban/tasks/main.yml << 'EOF'
---
- name: Install Fail2ban and rsyslog
  apt:
    name:
      - fail2ban
      - rsyslog
    state: present
    update_cache: yes

- name: Create auth.log if missing
  file:
    path: /var/log/auth.log
    state: touch
    owner: root
    mode: '0666'
  changed_when: false

- name: Deploy Fail2ban jail config
  copy:
    src: jail.local
    dest: /etc/fail2ban/jail.local
    owner: root
    group: root
    mode: '0644'
  notify: restart fail2ban

- name: Start Fail2ban
  service:
    name: fail2ban
    state: started
EOF
```

```bash
cat > /ansible/roles/fail2ban/handlers/main.yml << 'EOF'
---
- name: restart fail2ban
  service:
    name: fail2ban
    state: restarted
EOF
```

---

### Étape 9 — Rôle File Integrity

```bash
cat > /ansible/roles/file-integrity/files/file-monitor.sh << 'EOF'
#!/bin/bash
inotifywait -m -e modify,attrib,move,create,delete \
  /etc/passwd \
  /etc/shadow \
  /etc/ssh/sshd_config \
  >> /var/log/file-monitor.log 2>&1
EOF
```

```bash
cat > /ansible/roles/file-integrity/tasks/main.yml << 'EOF'
---
- name: Install inotify-tools
  apt:
    name: inotify-tools
    state: present
    update_cache: yes

- name: Create file-monitor log
  file:
    path: /var/log/file-monitor.log
    state: touch
    owner: root
    mode: '0644'
  changed_when: false

- name: Deploy file monitor script
  copy:
    src: file-monitor.sh
    dest: /usr/local/bin/file-monitor.sh
    owner: root
    group: root
    mode: '0755'

- name: Kill existing inotifywait if running
  shell: pkill -f inotifywait || true
  changed_when: false
  ignore_errors: yes

- name: Start file integrity monitor
  shell: setsid /usr/local/bin/file-monitor.sh &
  async: 10
  poll: 0
  ignore_errors: yes
  changed_when: false
EOF
```

---

### Étape 10 — Playbook principal

```bash
cat > /ansible/playbooks/site.yml << 'EOF'
---
- name: Harden target server
  hosts: all
  become: yes
  roles:
    - ssh-hardening
    - fail2ban
    - file-integrity
EOF
```

Lancer le playbook complet :

```bash
cd /ansible
ansible-playbook playbooks/site.yml
```

Résultat attendu : `changed=0 unreachable=0 failed=0`

---

### Étape 11 — Lancer la stack SOC (Loki + Grafana + Promtail)

Créer la config Promtail localement :

```powershell
# Contenu à sauvegarder dans hardened-infra/promtail-config.yml
```

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: hardened-server
    static_configs:
      - targets:
          - localhost
        labels:
          job: hardened-server
          __path__: /var/log/hardened/auth.log
```

Lancer les conteneurs :

```powershell
# Loki
docker run -d --name loki `
  --network hardened-net `
  -p 3100:3100 `
  grafana/loki:latest

# Grafana
docker run -d --name grafana `
  --network hardened-net `
  -p 3000:3000 `
  grafana/grafana:latest

# Promtail
docker run -d --name promtail `
  --network hardened-net `
  -v hardened-logs:/var/log/hardened:ro `
  -v C:\Users\khadija\hardened-infra\promtail-config.yml:/etc/promtail/config.yml `
  grafana/promtail:latest
```

---

### Étape 12 — Connecter Loki à Grafana

1. Ouvrir `http://localhost:3000` (admin/admin)
2. **Connections** → **Add new connection** → **Loki**
3. URL : `http://loki:3100`
4. **Save & test** → "Data source successfully connected"

---

### Étape 13 — Démarrer rsyslog sur ansible-target

```powershell
docker exec ansible-target bash -c "rsyslogd && chmod 666 /var/log/auth.log"
```

---

### Étape 14 — Créer le dashboard SOC

Dans Grafana → **Dashboards** → **New Dashboard** → ajouter ces panels :

**Panel 1 — Live log stream :**
```
{job="hardened-server"}
```
Type : Logs

**Panel 2 — Failed logins per minute :**
```
count_over_time({job="hardened-server"} |= "Failed" [1m])
```
Type : Time series

**Panel 3 — Bans Fail2ban :**
```
{job="hardened-server"} |= "Ban"
```
Type : Logs

Sauvegarder sous : **"Hardened Server SOC"**

---

### Étape 15 — Simuler une attaque et vérifier la détection

```powershell
for ($i=1; $i -le 10; $i++) {
  docker exec ansible-target ssh -o StrictHostKeyChecking=no root@localhost -p 2222
}
```

Observer le spike sur le dashboard Grafana — preuve que le pipeline fonctionne.

---

## Obstacles Rencontrés & Solutions

| Obstacle | Cause | Solution |
|---|---|---|
| Ansible locked out after hardening | `PermitRootLogin no` bloquait Ansible | Créer un user `ansible` dédié avec sudo |
| `changed_when: false` nécessaire | `touch` toujours compté comme changed | Ajouter `changed_when: false` |
| Promtail flag error | `--config.file` vs `-config.file` | Monter le config file directement via volume |
| Auth.log vide | rsyslog pas démarré | `rsyslogd && chmod 666 /var/log/auth.log` |
| Volume wrong path | promtail regardait le mauvais path | Recréer avec `-v hardened-logs:/var/log/hardened:ro` |
| SSH host key changed | Nouveau conteneur = nouvelle clé | `ssh-keygen -R 172.18.0.2` + `StrictHostKeyChecking=no` |
| Port 2222 après hardening | Inventaire pointait encore port 22 | Mettre à jour `ansible_port: 2222` dans hosts.yml |
| inotifywait tué par Ansible | Ansible kill ses child processes | Utiliser `setsid` + `async/poll: 0` |

---

## Leçons Clés

1. **Ne jamais automatiser en root** — toujours un user dédié avec sudo scopé
2. **Les volumes Docker sont la clé** — partager les logs entre conteneurs via volume nommé
3. **Idempotence** — un bon playbook Ansible donne `changed=0` à la deuxième exécution
4. **Tester chaque couche séparément** — pipeline = plusieurs points de défaillance possibles
5. **Documenter les obstacles** — chaque erreur est une preuve d'expérience réelle
