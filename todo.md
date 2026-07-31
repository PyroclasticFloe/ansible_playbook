# Todo
- The backups are failing to run. We need to fix them. Do this **first**. **Done**
- make sure that all variables are hooked up into the playbook
and that they do what they are supposed to. I've noticed that the
vaultwarden pod was getting started on desktop. It should be present, 
restore nightly but should not be started. I've disabled the timer but let's make sure the playbook doesn't reenable it on any host but prodesk. **Done**
- set up the playbook to use dnf and flatpak. **Done**
- make sure we can install on different hosts. I have server set up and waiting to run the playbook.
- containerize adguard home if possible.
    - This should run on prodesk, and be present but not active on desktop.
    - My router handles dhcp so we don't need to expose that.
    - I would really like to have DNS over HTTPS or TLS in my home network. This is a nice to have.
- prodesk (done last): add `docker-socket-proxy` to its `enabled_services` with
  `tailscale_hostname: prodesk-docker-proxy`, then append
  `prodesk-docker-proxy.<tailnet_domain>` to `homarr_docker_hostnames` in
  `ansible/host_vars/desktop.yml`.
- add `vault_homarr_secret_encryption_key` to `ansible/group_vars/all/vault.yml`
  (64-char hex; `openssl rand -hex 32`). Homarr will exit until it's set.
- homarr is currently `needs_backup: false`. Once it's stable, add a
  `desktop-homarr` passphrase to the vault and flip `needs_backup: true`.
- after first homarr run, verify it can resolve `<host>-docker-proxy.<tailnet_domain>`
  from inside its pod (MagicDNS). If not, substitute the proxies' tailnet IPs
  in `homarr_docker_hostnames`.
    