# Todo

## Completed
- Fix backups (borgmatic). **Done**
- Fix vaultwarden podman.socket enablement so it doesn't start on non-prodesk hosts. **Done**
- Set up playbook to use dnf and flatpak. **Done**
- Server set up and waiting to run the playbook. **Done**
- Add homarr with docker-socket-proxy cross-host Docker integration. **Done**
  - homarr running and responding on tailnet.
  - homarr `needs_backup: false` (flip later after stability).
- Add jellyfin as normal service on desktop (backs up to `desktop-jellyfin`). **Done**
- Add forgejo as restore-only on desktop (restoring from `prodesk-forgejo`, started manually). **Done**
- Fix `install_sidecar.yml` stat→delegate_to for remote hosts. **Done**
- Fix serve.json TCP forward (was incorrectly changed to Web/HTTPS). **Done**
- Fix inline `#` comments in quadlet `Volume=`/`Exec=` lines (jellyfin, homepage). **Done**
- Fix missing `/etc/containers/policy.json` on desktop (containers-common package file absent). **Done**
- Gitignore jellyfin var seed data (restore from backup instead). **Done**
- Revert jellyfin var un-gitignore in `.gitignore`. **Done**
- Add `vault_homarr_secret_encryption_key` to `ansible/group_vars/all/vault.yml` (64-char hex; `openssl rand -hex 32`). Homarr will exit until it's set. **Done**
- Verify homarr resolves `<host>-docker-proxy.<tailnet_domain>` from inside its pod (MagicDNS). If not, substitute proxies' tailnet IPs in `homarr_docker_hostnames`. **Done**
- Stop all services from getting a valkey directory in /var/lib/local_containers (only searxng needs it). Fix: snapshot `runtime_directories` per-service so it no longer leaks across service loops. **Done**
- The borg-backup-server `tmp/` chown issue is moot: BBS no longer places data in `/var/lib/local_containers`, and it's now `needs_backup: false`. **Done**
- services that are present but not active should be disabled, not enabled. Forgejo and Vaultwarden both start on desktop after a reboot. Fix: `systemd.yml` now sets `enabled: "{{ start_service }}"` so inactive services are disabled. **Done**
- Remove empty, unreferenced `common/tailscale/` (sidecar.container, sidecar.env) — install_sidecar.yml uses role templates instead. **Done**
- Wire BBS `ADMIN_PASS` from vault (`bbs_pass`) via an `env.j2` secrets file + `EnvironmentFile=` (was hardcoded empty in the quadlet). **Done**
- Fix searxng volume permissions surfacing after a while: seed step (`--chown=root:root`) was clobbering runtime-dir ownership, giving `root:root` dirs that valkey (uid 999) and searxng (uid 977) can't write (valkey MISCONF RDB, cache ownership warning). Move runtime-dir creation *after* seeding in `install_var.yml` and add `cache` (977) to searxng `runtime_directories`. **Done**
- Add prodesk to inventory with `docker-socket-proxy` (`tailscale_hostname: prodesk-docker-proxy`), append `prodesk-docker-proxy.<tailnet_domain>` to `homarr_docker_hostnames` in `ansible/host_vars/desktop.yml`, and gate borgmatic setup behind new `backup_enabled` host var (`false` on prodesk for now). **Done**
- Run vaultwarden and forgejo as non-root: the official images don't drop privileges (vaultwarden `start.sh` just execs the binary as root). Add `User=1000:1000` to both quadlets; data dirs must be owned `1000:1000`. **Done**
- Vaultwarden as uid 1000 couldn't bind port 80 (EACCES). Add `Sysctl=net.ipv4.ip_unprivileged_port_start=0` to the vaultwarden quadlet so the non-root uid can bind the port its serve.json proxies to. **Done**
- Forgejo failing to start with `Error: statfs /etc/timezone: no such file or directory`. Fedora has no `/etc/timezone` (Debian-only file). Remove the `/etc/timezone:/etc/timezone:ro,z` bind mount from `forgejo.container`; keep the `/etc/localtime` mount. **Done**
- Forgejo exiting 111 with `s6-svscan: fatal: unable to open .s6-svscan/lock: Permission denied` after adding `User=1000:1000`. The forgejo image's s6-overlay init (PID 1) must run as root; it drops to uid/gid 1000 for the forgejo process via `USER_UID`/`USER_GID`. Remove `User=1000:1000` from `forgejo.container`. **Done**
- Forgejo install page failing to write `/data/git/.ssh/authorized_keys` (permission denied): the forgejo container's git process is uid 1000, but the seeded var dir was root:root. Set `var_owner`/`var_group: "1000"` in `services/forgejo/defaults.yml`. **Done**
- Add BBS (Borg Backup Server) stop/start bracketing units. BBS schedules backups from the desktop controller but can't stop/start service containers, so each BBS-backed service gets `bbs-<host>-<svc>-stop.{service,timer}` and `-start.{service,timer}` units bracketing the backup window. Gated per-service by `bbs_backup`; times from `bbs_stop_time`/`bbs_start_time`. **Done**
- Replace BBS timer bracketing with agent pre/post-backup scripts. BBS agents can run shell scripts (via a plugin) around each backup, so the fixed stop/start timer window is no longer needed (avoids editing the playbook to change times, and avoids a mid-backup restart if the backup overruns the window). The shell-hook plugin config is **per-client** (attached to any of that client's backup plans), so only one generic script pair is installed per host (`/usr/local/lib/bbs/bbs-stop.sh` + `bbs-start.sh`). The scripts parse `BBS_BACKUP_PLAN` (last `-` token) to stop/start only the service being backed up. Host-level `bbs_use_agent_scripts` (default `false`) switches a host to the scripts; when true, the old `install_bbs.yml` timer units are skipped (files/templates kept for rollback). Enabled on prodesk and desktop; point each client's shell-hook plugin at the two script paths. **Done**
- Fix var dir ownership for non-root containers. The "Fix var directory ownership" task in `install_var.yml` recursively chowns `<var_dir>` when `var_owner`/`var_group` are set in the service defaults. Set on jellyfin, forgejo, homepage, and vaultwarden (all run as 1000:1000). SearXNG is handled per-subdir via `runtime_directories` (valkey 999:1000, cache 977:977). BBS (uid 33) writes only to `/mnt/backup/bbs`, which is left unmanaged by the playbook. **Done**
- Ideally, we should not be seeding data once the BBS is up. The var directory should only have .keep for each service, etc should only contain persistent settings and the tailscale/serve.json. **Done**
- SearXNG has a secret key in its settings.yml. Let's set it up to read that from an env file in the same directory and make sure that's backed up. Or just remove it from git and rely on the backup. **File removed from git**

## Pending
- Containerize adguard home if possible.
  - Should run on prodesk, present but not active on desktop.
  - Router handles DHCP so no port exposure for dhcp needed.
  - DNS over HTTPS/TLS in home network is a nice to have.
  - Base container wired: runs as 1000:1000, `AddCapability=CAP_NET_RAW` (image already file-caps `cap_net_bind_service`), no host port binds (web UI proxied via tailscale serve → 127.0.0.1:3000), DoT/DoH and serving DNS to the LAN still pending.
- Homepage can't ping services on the tailnet. Example:
```
podman exec -it systemd-homepage sh
/app $ ping https://llama-swap.tail044fe.ts.net/
```
  ping: socktype: SOCK_RAW
  ping: socket: Operation not permitted
  ping: => missing cap_net_raw+p capability or setuid?
```
  Possibly the same solution as adguard home?
  
- Clean up the previous (borgmatic) backup system. The tasks and related files can probably be moved to a containers/old_tasks/old_backup directory.
 in the playbook and move them under the containers/old_tasks directory.
 - General cleanup. Look for any tasks, variables, files no longer used

