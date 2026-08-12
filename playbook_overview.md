# Ansible Playbook Overview

## Directory structure

```
ansible/
├── inventory                    # Host inventory
├── playbook.yml                 # Top-level playbook (entry point)
├── group_vars/all/
│   ├── vars                     # Global vars (tailnet_domain, is_gui, …)
│   └── vault.yml                # Encrypted secrets
├── host_vars/
│   └── desktop.yml              # Per-host service list + overrides
└── roles/containers/
    ├── defaults/main.yml        # Role-level defaults
    ├── handlers/main.yml        # Handlers (Restart service, Reload systemd)
    ├── tasks/
    │   ├── main.yml             # Per-service orchestration
    │   ├── install_bbs_scripts.yml # BBS agent pre/post-backup scripts (per-service)
    │   ├── install_service.yml  # Deploys static config files
    │   ├── install_secrets.yml  # Renders env.j2 secrets template
    │   ├── install_var.yml      # Creates runtime directories + seeds data
    │   ├── install_quadlets.yml # Installs podman quadlet files
    │   ├── install_sidecar.yml  # Tailscale sidecar container
    │   └── systemd.yml          # Enables/stops systemd units
        └── templates/               # Jinja2 templates
            ├── bbs_service_start.j2
            ├── bbs_service_stop.j2
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

## Playbook flow

```
playbook.yml
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
│
└── Install BBS agent scripts (once per host, when bbs_use_agent_scripts=true):
    install_bbs_scripts.yml → bbs-stop.sh / bbs-start.sh to
    /usr/local/lib/bbs/; each parses BBS_BACKUP_PLAN to stop/start only the
    service being backed up
```

The old borgmatic backup system was retired and its files moved to
`old_tasks/old_backup/` (see the git history there); backups now run via
BBS (Borg Backup Server).

## Task file details

| Task file | Purpose |
|---|---|
| `main.yml` | Per-service entry point. Loads service defaults, computes systemd unit names, then includes the sub-tasks below in sequence. |
| `install_service.yml` | Creates `<etc_dir>` and copies files from `services/<name>/etc/` into it. Notifies `Restart service` handler on change. |
| `install_secrets.yml` | If `services/<name>/env.j2` exists, renders it to `<etc_dir>/<name>.env` (mode 0600). Notifies `Restart service` on change. |
| `install_var.yml` | Creates `<var_dir>` and any extra `runtime_directories` listed in the service's defaults.yml. Seeds data from `services/<name>/var/` (won't overwrite existing files). `runtime_directories` is captured per-service into `service_runtime_directories` in `main.yml` so a value from one service (e.g. searxng's `valkey`) doesn't leak into others via `include_vars` play-scope persistence. Runtime subdirs are created *after* seeding so the seed step's `--chown=root:root` can't overwrite the non-root ownership they need (e.g. valkey uid 999, searxng uid 977). |
| `install_quadlets.yml` | Copies `services/<name>/quadlets/` to `/etc/containers/systemd/<name>/`. Notifies `Restart service` on change. |
| `install_sidecar.yml` | Creates Tailscale state dir, config dir, renders `tailscale.container` and `tailscale.env` templates. Runs only when `tailscale: true`. Validates that `serve.json` and auth key exist. |
| `systemd.yml` | Runs `systemctl daemon-reload`, then enables each systemd unit and sets it to `started` or `stopped` based on `start_service`. |
| `install_bbs_scripts.yml` | When `bbs_use_agent_scripts` is true (host-level), installs `bbs-stop.sh` / `bbs-start.sh` (mode 0755) to `/usr/local/lib/bbs/`. The BBS shell-hook plugin config is per-client: attach it to any of that client's backup plans, and the agent runs the stop script before and the start script after each backup. The scripts parse `BBS_BACKUP_PLAN` (last `-`-delimited token) to stop/start only the service being backed up, and use `set -euo pipefail` so a failed stop aborts the backup. |

## Handlers

| Handler | Action |
|---|---|
| `Restart service` | Appends the current `systemd_units` list to the `changed_units` fact. Collected across all services; at the end of the playbook the accumulated list is restarted. |
| `Reload systemd` | Runs `systemctl daemon-reload`. Used by tasks that write new unit files. |

## Built-in variables

Set in `defaults/main.yml` (can be overridden per-service in `desktop.yml` as a dict):

| Variable | Default | Description |
|---|---|---|
| `start_service` | `true` | Whether the systemd units are started (`true`) or stopped (`false`) |
| `bbs_use_agent_scripts` | `false` | **Host-level** (set in `host_vars/<host>.yml`, not per-service). When true, installs the BBS agent stop/start scripts (`/usr/local/lib/bbs/`). The shell-hook plugin config is per-client, so one generic script pair handles every backup plan on the host. |
| `pod_enabled` | `true` | Whether a pod quadlet wraps the service container |
| `var_owner` | — | Recursively chown `<var_dir>` to this uid after seeding (with `var_group`, defaulting to `var_owner`). Set when the container runs as a non-root user so it can write its bind mounts. |
| `tailscale_hostname` | `service_name` | Tailnet node name for the sidecar (`TS_HOSTNAME`). Override per-host so a service deployed on several hosts (e.g. `docker-socket-proxy` → `desktop-docker-proxy`) gets a unique `*.ts.net` name on each. |

Set in `group_vars/all/vars`:

| Variable | Description |
|---|---|
| `tailnet_domain` | Tailscale MagicDNS domain (e.g. `tail044fe.ts.net`), used to build cross-host names |
| `is_gui` | Whether this host gets GUI packages (default `false`) |
| `is_nvidia` | Whether this host has an Nvidia GPU (default `false`) |

Set in `group_vars/all/vault.yml` (ansible-vault encrypted):

| Variable | Description |
|---|---|
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
   - As a dict with overrides if any differ from defaults: `- name: <name> start_service: false …`
3. If the service is backed up by BBS (Borg Backup Server), attach the stop/start shell-hook scripts (see `install_bbs_scripts.yml`) to that client's backup plan in BBS.

> **Note:** Seed data is copied as root, so any service whose container drops to a non-root user must set `var_owner`/`var_group` in its `defaults.yml` to match that user's uid/gid (e.g. `1000:1000` for jellyfin/homepage/vaultwarden/forgejo). The "Fix var directory ownership" task in `install_var.yml` then recursively chowns `<var_dir>` after seeding. For per-subdir ownership (e.g. searxng's valkey/cache), use `runtime_directories` entries with `owner`/`group` instead.

## How to add a new host

1. Create `host_vars/<host>.yml` with `enabled_services` listing each service
2. Add the host to `inventory` with its connection details
3. Add any host-specific overrides to `host_vars/<host>.yml`
4. Run `ansible-playbook -i ansible/inventory ansible/playbook.yml --ask-vault-pass`
