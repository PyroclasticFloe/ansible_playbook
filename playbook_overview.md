# Ansible Playbook Overview

## Directory structure

```
ansible/
├── inventory                    # Host inventory
├── playbook.yml                 # Top-level playbook (entry point)
├── group_vars/all/
│   ├── vars                     # Global vars (backup_time, rsync_net_login)
│   └── vault.yml                # Encrypted backup passphrases
├── host_vars/
│   └── desktop.yml              # Per-host service list + overrides
└── roles/containers/
    ├── defaults/main.yml        # Role-level defaults
    ├── handlers/main.yml        # Handlers (Restart service, Reload systemd)
    ├── tasks/
    │   ├── main.yml             # Per-service orchestration
    │   ├── install_borgmatic.yml # Borgmatic setup (runs once per host)
    │   ├── install_service.yml  # Deploys static config files
    │   ├── install_secrets.yml  # Renders env.j2 secrets template
    │   ├── install_var.yml      # Creates runtime directories + seeds data
    │   ├── install_quadlets.yml # Installs podman quadlet files
    │   ├── install_sidecar.yml  # Tailscale sidecar container
    │   └── systemd.yml          # Enables/stops systemd units
    └── templates/               # Jinja2 templates
        ├── backup_host_service.j2
        ├── backup_container_service.j2
        ├── backup_timer.j2
        ├── restore_borgmatic.j2
        ├── restore_service.j2
        ├── restore_timer.j2
        ├── service_borgmatic.j2
        ├── tailscale.container.j2
        └── tailscale.env.j2
```

```
services/
├── <name>/
│   ├── defaults.yml             # Service-level Ansible vars (tailscale, runtime_directories, …)
│   ├── etc/                     # Static config files → /etc/local_containers/<name>/
│   ├── var/                     # Runtime data seeds → /var/lib/local_containers/<name>/
│   ├── quadlets/                # Podman .container/.pod files → /etc/containers/systemd/<name>/
│   └── env.j2                   # (Optional) secrets template → <etc_dir>/<name>.env
```

## What the playbook does

The playbook (`ansible/playbook.yml`) installs containerised services on a single host.
Each container runs under podman via quadlet files (systemd units). Services can optionally:

- Use Tailscale as a sidecar for private networking
- Be backed up to rsync.net via borgmatic
- Be restored (read-only extract) from a remote borg repo

## Playbook flow

```
playbook.yml
├── install_borgmatic.yml     ← runs once per host (not per-service); skipped when backup_enabled=false
│   ├── Install borgmatic & borg packages
│   ├── Copy SSH automation key to /root/.ssh/
│   ├── For each service with needs_backup=true:
│   │   ├── Create borgmatic config (/etc/borgmatic/borgmatic.d/<host>-<service>.yaml)
│   │   ├── Create systemd backup service
│   │   └── Create systemd backup timer
│   ├── Create host-level borgmatic service + timer (/etc/borgmatic/borgmatic.d/<host>-host.yaml)
│   ├── Enable & start all backup timers
│   ├── For each service with needs_restore=true:
│   │   ├── Create restore borgmatic config (/etc/borgmatic/borgmatic.d/restore_<service>.yaml)
│   │   ├── Create systemd restore service
│   │   ├── Create systemd restore timer
│   │   └── Enable & start restore timer
│   │
│   └── (SSH key, directory setup, etc.)
│
└── Enable podman.socket      ← host-level Docker-compatible API socket
                                   (/run/podman/podman.sock), used by the
                                   docker-socket-proxy service
│
└── Ensure /etc/containers/policy.json   ← required by podman before it
                                   will pull any image; write the default
                                   (insecureAcceptAnything) if missing
│
└── For each service in enabled_services:
    └── main.yml (role entry point)
        ├── Load service defaults.yml
        ├── Compute systemd unit list (pod, service, sidecars)
        ├── install_service.yml     → create etc_dir, copy static config
        ├── install_secrets.yml     → render env.j2 if present
        ├── install_var.yml         → create var_dir, seed runtime data
        ├── install_quadlets.yml    → deploy .container/.quadlet files
        ├── install_sidecar.yml     → Tailscale container (if tailscale=true)
        ├── flush_handlers          → restart service if config/secrets changed
        └── systemd.yml             → enable/start (or stop) systemd units
```

## Task file details

| Task file | Purpose |
|---|---|
| `install_borgmatic.yml` | Installs borg/borgmatic, copies SSH key to root, creates per-service borgmatic configs + systemd timers, creates host-level backup, creates restore configs/timers, enables everything. Runs once per host (not per-service loop). |
| `main.yml` | Per-service entry point. Loads service defaults, computes systemd unit names, then includes the sub-tasks below in sequence. |
| `install_service.yml` | Creates `<etc_dir>` and copies files from `services/<name>/etc/` into it. Notifies `Restart service` handler on change. |
| `install_secrets.yml` | If `services/<name>/env.j2` exists, renders it to `<etc_dir>/<name>.env` (mode 0600). Notifies `Restart service` on change. |
| `install_var.yml` | Creates `<var_dir>` and any extra `runtime_directories` listed in the service's defaults.yml. Seeds data from `services/<name>/var/` (won't overwrite existing files). `runtime_directories` is captured per-service into `service_runtime_directories` in `main.yml` so a value from one service (e.g. searxng's `valkey`) doesn't leak into others via `include_vars` play-scope persistence. Runtime subdirs are created *after* seeding so the seed step's `--chown=root:root` can't overwrite the non-root ownership they need (e.g. valkey uid 999, searxng uid 977). |
| `install_quadlets.yml` | Copies `services/<name>/quadlets/` to `/etc/containers/systemd/<name>/`. Notifies `Restart service` on change. |
| `install_sidecar.yml` | Creates Tailscale state dir, config dir, renders `tailscale.container` and `tailscale.env` templates. Runs only when `tailscale: true`. Validates that `serve.json` and auth key exist. |
| `systemd.yml` | Runs `systemctl daemon-reload`, then enables each systemd unit and sets it to `started` or `stopped` based on `start_service`. |

## Handlers

| Handler | Action |
|---|---|
| `Restart service` | Appends the current `systemd_units` list to the `changed_units` fact. Collected across all services; at the end of the playbook the accumulated list is restarted. |
| `Reload systemd` | Runs `systemctl daemon-reload`. Used by borgmatic tasks that write new unit files. |

## Built-in variables

Set in `defaults/main.yml` (can be overridden per-service in `desktop.yml` as a dict):

| Variable | Default | Description |
|---|---|---|
| `needs_backup` | `true` | Whether borgmatic configs + backup timers are created for this service |
| `start_service` | `true` | Whether the systemd units are started (`true`) or stopped (`false`) |
| `needs_restore` | `false` | Whether restore (borg extract) timer is created for this service |
| `restore_time` | `"04:00"` | `OnCalendar` time for the restore timer |
| `restore_from_repo` | — | SSH URL of the remote borg repo to restore from (e.g. `ssh://de5097@de5097.rsync.net/./prodesk-forgejo`) |
| `restore_from_label` | — | Label (key into `vault_backup_passphrases`) identifying the source repo's encryption passphrase |
| `restore_from_host` | — | Hostname of the source host (used to match archive prefix `sh:<host>-*`) |
| `backup_frequency` | `"1 day"` | (Reserved for future per-service timer offset) |
| `pod_enabled` | `true` | Whether a pod quadlet wraps the service container |
| `tailscale_hostname` | `service_name` | Tailnet node name for the sidecar (`TS_HOSTNAME`). Override per-host so a service deployed on several hosts (e.g. `docker-socket-proxy` → `desktop-docker-proxy`) gets a unique `*.ts.net` name on each. |

Set in `group_vars/all/vars`:

| Variable | Description |
|---|---|
| `backup_time` | Anchor time (HH:MM) for all backup timers |
| `rsync_net_login` | rsync.net SSH login (e.g. `de5097@de5097.rsync.net`) |
| `tailnet_domain` | Tailscale MagicDNS domain (e.g. `tail044fe.ts.net`), used to build cross-host names |
| `backup_enabled` | Whether this host runs borgmatic backups (default `true`). Set `false` per-host to skip all backup setup — used for prodesk until it's a stable backup writer |
| `is_gui` | Whether this host gets GUI packages (default `false`) |
| `is_nvidia` | Whether this host has an Nvidia GPU (default `false`) |

Set in `group_vars/all/vault.yml` (ansible-vault encrypted):

| Variable | Description |
|---|---|
| `vault_backup_passphrases` | Dict keyed by `<host>-<service_name>` mapping to each backup repo's encryption passphrase |
| `vault_homarr_secret_encryption_key` | 64-char hex key required for homarr to start; must be set in `ansible/group_vars/all/vault.yml` |

## How Homarr sees containers across hosts

Homarr's Docker integration is limited to Unix sockets mounted into its own
container, so remote hosts can't be reached that way. Instead:

- Each host that runs services deploys the `docker-socket-proxy` service — a
  [Tecnativa socket proxy](https://github.com/Tecnativa/docker-socket-proxy)
  container that exposes the host's `/run/podman/podman.sock` (read-only:
  `CONTAINERS=1`, `POST=0`) on TCP `2375` inside its pod.
- The service's Tailscale sidecar forwards that port onto the tailnet via raw
  TCP in `serve.json`, so each host's proxy is reachable at
  `<host>-docker-proxy.<tailnet_domain>:2375` (e.g. `server-docker-proxy.tail044fe.ts.net`).
  Give each proxy a unique `tailscale_hostname` per host to keep tailnet names distinct.
- Homarr (on its own host) connects to the proxies over the tailnet via
  `DOCKER_HOSTNAMES` + `DOCKER_PORTS` in `homarr.env`, rendered from the
  `homarr_docker_hostnames` / `homarr_docker_ports` host vars.

`podman.socket` must be enabled on each host for the socket path to exist; the
playbook does this at the start of the containers play.

## How to add a new service

1. Create `services/<name>/` with the following files:
   - **`defaults.yml`** — set at least `tailscale: true` if needed, plus any `runtime_directories` entries
   - **`etc/`** — static files that get copied to `/etc/local_containers/<name>/`
   - **`var/`** — seed data for `/var/lib/local_containers/<name>/` (copied once, won't overwrite existing)
   - **`quadlets/`** — podman quadlet files (`.container`, `.pod`, etc.)
   - **`env.j2`** (optional) — Jinja2 template rendered to `<name>.env` with mode `0600`; reference vault variables here
2. Add the service name to `enabled_services` in the host's `host_vars/<host>.yml`:
   - As a plain string if all defaults apply: `- <name>`
   - As a dict with overrides if any differ from defaults: `- name: <name> needs_backup: false start_service: false …`
3. If the service needs **backup**: ensure `needs_backup` is `true` (default), and add the encryption passphrase to `group_vars/all/vault.yml` under `vault_backup_passphrases[<host>-<name>]`
4. If the service needs **restore** (reader mode): set `needs_restore: true` and supply `restore_from_repo` + `restore_from_label` + `restore_from_host` in the host vars dict. The vault key lookup uses `restore_from_label` as the index into `vault_backup_passphrases`.

> **Note:** Services that seed runtime data via `var/` (e.g. jellyfin) may need `chown -R 1000:1000 <var_dir>` after the first `install_var.yml` run, since seed data is copied as root. This should be automated in the playbook in a future update.

## How to add a new host

1. Create `host_vars/<host>.yml` with `enabled_services` listing each service
2. Add the host to `inventory` with its connection details
3. Generate an SSH automation key on the new host (`ssh-keygen -t ed25519 -f ~/.ssh/<host>_rsync_net_ecdsa -N ""`) and append its public key to the rsync.net `authorized_keys`
4. If the host runs backup writers, add each `<host>-<service>` passphrase to `vault.yml`; leave `backup_enabled: false` in the host vars until then
5. Add any host-specific overrides to `host_vars/<host>.yml`
6. Run `ansible-playbook -i ansible/inventory ansible/playbook.yml --ask-vault-pass`
