# Borg / Borgmatic Backup System — Cheat Sheet

Built for: prodesk (source), with desktop/laptop/server as vaultwarden readers.
Remote: rsync.net (account `de5097`, host `de5097.rsync.net`, remote borg version `borg14`).

---

## 1. Two kinds of secrets — don't confuse them

| Secret | What it's for | Shared across machines? | Where it lives |
|---|---|---|---|
| **SSH key** | Proves *which machine* is allowed to talk to the repo (transport/auth layer) | No — one keypair per machine/role | `~/.ssh/` locally, public half in rsync.net's `authorized_keys` |
| **Borg repo passphrase** | Encrypts/decrypts the *repo contents* itself | Yes, for repos multiple machines read (e.g. vaultwarden) — every reader needs the same passphrase | `encryption_passphrase:` in each borgmatic yaml, plus stored in Vaultwarden + physical backup |

**No, the `borg init` passphrase does not correspond to any SSH key.** They're independent secrets serving different jobs — SSH controls *can this machine connect at all*, the passphrase controls *can this machine read what's inside*. A machine could have SSH access but the wrong passphrase (gets in, can't decrypt), or vice versa isn't possible (no SSH access means it never reaches the point of needing the passphrase).

---

## 2. SSH keys inventory

| Key | Used by | Passphrase? | Stored where |
|---|---|---|---|
| Personal/interactive key (e.g. `id_ecdsa`) | You, manually, from desktop | **Yes** — protected, unlocked via KWallet agent at login | `~/.ssh/id_ecdsa` (aria's home only) |
| Per-host automation key (e.g. `prodesk_rsync_net_ecdsa`) | borgmatic, unattended, run as root via systemd | **No** — must be passphrase-less since nothing is present to type it in at 2am | Copied to **both** the human user's home AND root's home (see below) |

### Why the automation key needs a root copy

Systemd `.service` units with no `User=` line run as **root**, not as your regular user. Root has its own `~/.ssh/` (`/root/.ssh/`), completely separate from `/home/aria/.ssh/`. If the automation key only exists in your user's home, root-run borgmatic can't find it and SSH falls back to a password prompt — which will hang forever on an unattended timer.

**Command to copy the automation key to root, per host:**
```bash
sudo mkdir -p /root/.ssh
sudo cp ~/.ssh/<host>_rsync_net_ecdsa /root/.ssh/
sudo chown root:root /root/.ssh/<host>_rsync_net_ecdsa
sudo chmod 600 /root/.ssh/<host>_rsync_net_ecdsa
```

Then reference it explicitly in every borgmatic yaml for that host (don't rely on `~/.ssh/config` matching — root won't read your user's config file):
```yaml
ssh_command: ssh -i /root/.ssh/<host>_rsync_net_ecdsa -o StrictHostKeyChecking=accept-new
```
`StrictHostKeyChecking=accept-new` auto-trusts the host key on first contact (root's `known_hosts` is separate from your user's, so it hasn't trusted rsync.net yet either) without blocking on an interactive prompt, while still refusing to proceed silently if the key ever *changes* later.

### Generating a new automation key (per host)
```bash
ssh-keygen -t ed25519 -f ~/.ssh/<host>_rsync_net_ecdsa -C "<host>-borg@rsync.net" -N ""
```
`-N ""` sets an empty passphrase up front, non-interactively.

### Uploading a new public key to rsync.net (append, never overwrite!)

rsync.net's restricted shell doesn't support pipes/chaining in remote commands, so use their documented safe-append form:
```bash
cat ~/.ssh/<host>_rsync_net_ecdsa.pub | ssh <user>@<pod>.rsync.net 'dd of=.ssh/authorized_keys oflag=append conv=notrunc'
```
⚠️ Never use plain `scp key.pub user@host:.ssh/authorized_keys` — `scp` overwrites the destination file, wiping out every other key already authorized.

**Verify after any change:**
```bash
ssh <user>@<pod>.rsync.net "cat .ssh/authorized_keys"
```
Confirm every expected key is present as its own line before moving on.

---

## 3. File locations (with example contents)

### Borgmatic configs — `/etc/borgmatic/borgmatic.d/<name>.yaml`

One file per backup job (a "job" = one source + one schedule + one repo destination). Multiple jobs *can* share a repo (forgejo + prodesk-host do), each with its own prefix so retention doesn't cross-prune.

```yaml
# /etc/borgmatic/borgmatic.d/vaultwarden.yaml
source_directories:
    - /home/aria/docker/vaultwarden/vw-data

repositories:
    - path: ssh://de5097@de5097.rsync.net/./vaultwarden
      label: vaultwarden

encryption_passphrase: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
remote_path: borg14
ssh_command: ssh -i /root/.ssh/prodesk_rsync_net_ecdsa -o StrictHostKeyChecking=accept-new
compression: auto,zstd

keep_within: 2d
keep_daily: 14
keep_weekly: 8
keep_monthly: 6

checks:
    - name: repository
    - name: archives
      frequency: 2 weeks

commands:
    - before: action
      when: [create]
      run:
          - docker compose -f /home/aria/docker/vaultwarden/compose.yaml stop vaultwarden
    - after: action
      when: [create]
      run:
          - docker compose -f /home/aria/docker/vaultwarden/compose.yaml start vaultwarden
```

```yaml
# /etc/borgmatic/borgmatic.d/forgejo.yaml  (shares the prodesk_host repo)
source_directories:
    - /mnt/data/forgejo-data

repositories:
    - path: ssh://de5097@de5097.rsync.net/./prodesk_host
      label: prodesk_host

archive_name_format: 'forgejo-{now}'
encryption_passphrase: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
remote_path: borg14
ssh_command: ssh -i /root/.ssh/prodesk_rsync_net_ecdsa -o StrictHostKeyChecking=accept-new
compression: auto,zstd

keep_daily: 7
keep_weekly: 4
keep_monthly: 6
prefix: 'forgejo-'

commands:
    - before: action
      when: [create]
      run:
          - docker compose -f /home/aria/docker/forgejo/compose.yaml stop forgejo
    - after: action
      when: [create]
      run:
          - docker compose -f /home/aria/docker/forgejo/compose.yaml start forgejo
```

```yaml
# /etc/borgmatic/borgmatic.d/prodesk-host.yaml  (shares the prodesk_host repo, no live services)
source_directories:
    - /etc/ssh
    - /home/aria/.ssh
    - /etc/borgmatic/borgmatic.d

repositories:
    - path: ssh://de5097@de5097.rsync.net/./prodesk_host
      label: prodesk_host

archive_name_format: 'prodesk-host-{now}'
encryption_passphrase: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
remote_path: borg14
ssh_command: ssh -i /root/.ssh/prodesk_rsync_net_ecdsa -o StrictHostKeyChecking=accept-new
compression: auto,zstd

keep_daily: 7
keep_weekly: 4
keep_monthly: 6
prefix: 'prodesk-host-'
```

### Systemd units — `/etc/systemd/system/borgmatic-<name>.{service,timer}`

```ini
# /etc/systemd/system/borgmatic-vaultwarden.service  (key lines only — rest is the packaged hardening defaults)
[Service]
Type=oneshot
LoadCredentialEncrypted=borgmatic.pw
ExecStartPre=sleep 1m
ExecStart=systemd-inhibit --who="borgmatic" --what="sleep:shutdown" --why="Prevent interrupting scheduled backup" /usr/bin/borgmatic --config /etc/borgmatic/borgmatic.d/vaultwarden.yaml --verbosity -2 --syslog-verbosity 1
```

```ini
# /etc/systemd/system/borgmatic-vaultwarden.timer
[Timer]
OnCalendar=*:0/30
Persistent=true
RandomizedDelaySec=2m
```

```ini
# /etc/systemd/system/borgmatic-forgejo.timer
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=5m
```

```ini
# /etc/systemd/system/borgmatic-prodesk-host.timer
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=5m
```

> Stagger timers sharing a repo (forgejo + prodesk-host) with enough gap that jitter can't cause them to overlap — Borg repos are single-writer, even from the same machine.

### SSH config — `~/.ssh/config` (your interactive user)

```
Host de5097.rsync.net
    User de5097
    IdentityFile ~/.ssh/id_ecdsa
    IdentitiesOnly yes
```

### SSH keys on disk

```
~/.ssh/id_ecdsa                          # your personal key, passphrase-protected, KWallet-managed
~/.ssh/<host>_rsync_net_ecdsa            # this host's automation key, no passphrase
/root/.ssh/<host>_rsync_net_ecdsa        # same automation key, copied for root/systemd use
```

### Remote — rsync.net's `authorized_keys`

Not on your machine — lives at `~/.ssh/authorized_keys` on the rsync.net account itself. Contains one line per authorized public key (your interactive key + every host's automation key that needs access).

---

## 4. Borg / Borgmatic commands

Every command below assumes you're pointing at a specific config: `--config /etc/borgmatic/borgmatic.d/<name>.yaml`. Run as `sudo` on any host where the config uses the root-owned automation key.

### Init a new repo (once, ever, per repo)
```bash
borg init --encryption repokey-blake2 --remote-path=borg14 ssh://de5097@de5097.rsync.net/./<repo-name>
```
Prompts for a passphrase — generate fresh, unique, save to Vaultwarden **and** physical backup immediately.

### Create a backup
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml create --verbosity 1 --list --stats
```
- `--list` — show each file as it's archived
- `--stats` — size/dedup summary at the end
- Drop both flags for the quiet version cron/systemd actually runs

### List archives in a repo
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml list
```

### List files inside one specific archive
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml list --archive latest
```

### Explore a repo without extracting (FUSE mount)
```bash
mkdir -p /tmp/borg_mount
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml mount --archive latest --mount-point /tmp/borg_mount
# ... browse /tmp/borg_mount like a normal directory ...
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml umount --mount-point /tmp/borg_mount
```

### Restore / extract

Whole archive, to a scratch directory (never extract straight over live data):
```bash
mkdir -p /tmp/restore_test
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml extract --archive latest --destination /tmp/restore_test
```

Just one path from the archive:
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml extract --archive latest --path home/aria/docker/vaultwarden/vw-data --destination /tmp/restore_test
```

Strip the leading directory structure on extraction:
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml extract --archive latest --destination /tmp/restore_test --strip-components all
```

### Verify repo/archive integrity
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml check
```
(Also runs automatically per the `checks:` section in each yaml, on the stated frequency.)

### Compare two archives
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml --archive <older> --archive2 <newer>
```
(or plain borg: `borg diff repo::archive1 repo::archive2`)

### Prune old archives manually (normally automatic via retention settings)
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml prune --list --stats
```

### Reclaim disk space after pruning
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml compact
```

### Export the repo encryption key (do this once per repo, store with your other physical secrets)
```bash
borg key export --remote-path=borg14 ssh://de5097@de5097.rsync.net/./<repo-name> /path/to/save/<repo-name>.key
```

### Repo info (size, archive count, etc.)
```bash
sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml info
```

---

## 5. Checklist: adding a new host or service

1. **Generate the automation key on the new host:**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/<host>_rsync_net_ecdsa -C "<host>-borg@rsync.net" -N ""
   ```
2. **Append its public key to rsync.net** (from any machine that already has access):
   ```bash
   cat ~/.ssh/<host>_rsync_net_ecdsa.pub | ssh <user>@<pod>.rsync.net 'dd of=.ssh/authorized_keys oflag=append conv=notrunc'
   ```
3. **Copy the key to root** on the new host (needed for systemd, see §2):
   ```bash
   sudo mkdir -p /root/.ssh
   sudo cp ~/.ssh/<host>_rsync_net_ecdsa /root/.ssh/
   sudo chown root:root /root/.ssh/<host>_rsync_net_ecdsa
   sudo chmod 600 /root/.ssh/<host>_rsync_net_ecdsa
   ```
4. **Init the repo** (skip if reusing an existing repo, e.g. a new *reader* for vaultwarden):
   ```bash
   borg init --encryption repokey-blake2 --remote-path=borg14 ssh://de5097@de5097.rsync.net/./<repo-name>
   ```
   Save the passphrase to Vaultwarden + physical backup immediately.
5. **Write the borgmatic yaml** under `/etc/borgmatic/borgmatic.d/`, using the templates in §3 as a base.
6. **Write matching systemd `.service` + `.timer`** files, cloned from an existing pair — check for repo-sharing conflicts and stagger timers accordingly.
7. **Test manually before enabling the timer:**
   ```bash
   sudo borgmatic --config /etc/borgmatic/borgmatic.d/<name>.yaml create --verbosity 1 --list --stats
   ```
   Confirm: no password prompt, no deprecation warnings, hooks fire correctly if applicable.
8. **Enable the timer:**
   ```bash
   sudo systemctl enable --now borgmatic-<name>.timer
   systemctl list-timers 'borgmatic-*'
   ```
9. **Do a test restore** (§4 "Restore / extract") into a scratch directory and confirm the data is actually usable (integrity check, diff against live, or spin up the real service against it) before trusting the job.

---

## 6. Quick reference — reader vs. writer for shared repos (e.g. vaultwarden)

- **Writer** (currently prodesk): runs `create`, has a `commands:` hook stopping/starting the container.
- **Reader** (desktop/laptop/server): runs `extract` on a schedule instead of `create`; container stays stopped; same repo path + same encryption passphrase as the writer, but its own SSH key restricted (ideally via an `authorized_keys` forced command) to read-only/append-only access so it structurally cannot write even by accident.
- **Failover**: promote a reader by (a) stopping it from being a reader, (b) flipping its config to a writer role (`create` + hooks), (c) starting the container on it, (d) disabling the old writer's config so it doesn't try to write again if it comes back online unexpectedly.
