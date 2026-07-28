# Todo
- The backups are failing to run. We need to fix them. Do this **first**. **Done**
- make sure that all variables are hooked up into the playbook
and that they do what they are supposed to. I've noticed that the
vaultwarden pod was getting started on desktop. It should be present, 
restore nightly but should not be started. I've disabled the timer but let's make sure the playbook doesn't reenable it on any host but prodesk.
- set up the playbook to use dnf and flatpak.
- make sure we can install on different hosts. I have server set up and waiting to run the playbook.
- containerize adguard home if possible.
    - This should run on prodesk, and be present but not active on desktop.
    - My router handles dhcp so we don't need to expose that.
    - I would really like to have DNS over HTTPS or TLS in my home network. This is a nice to have.
    