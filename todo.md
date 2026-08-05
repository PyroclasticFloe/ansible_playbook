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
## Pending
- Flip homarr `needs_backup` to `true` after stability confirmed; add `desktop-homarr` passphrase to vault. **Delay. The backup system is changing**
- Add post-install `chown -R 1000:1000 /var/lib/local_containers/jellyfin/` task to playbook (jellyfin seed data copied as root by `install_var.yml`).
- Containerize adguard home if possible.
  - Should run on prodesk, present but not active on desktop.
  - Router handles DHCP so no port exposure needed.
  - DNS over HTTPS/TLS in home network is a nice to have.
