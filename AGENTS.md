You are helping to design and implement an ansible playbook that will do the following:
- set up 4 hosts
    - desktop is the first, gui with AMD GPU
    - server is the next. It has Nvidia GPU and is usually run headless
    - laptop is configured similarly to desktop
    - prodesk will be done last
- install a common set of cli utilities on each host
    - these are installed with dnf by the playbook
- install a set of gui apps on desktop and laptop
    - Some will be installed with dnf, others with flatpak
- install a set of podman containers that vary for each host
    - these are rootful containers managed by systemd
    - vaultwarden should be present on all hosts but only started on
    prodesk. This way I have access to my passwords at all times.
- configure a backup system with borgmatic backing up to rsync.net
    - each host should have its own backup schedule so that no two
    hosts are accessing the same borg repo at the same time.

When starting to make changes, create a feature branch and only work within that branch. When the feature is complete and tested, add, commit and merge then notify the user. The user will handle git push.

Comments should be used only when the purpose of the code is unclear.

When accessing files in the containers repo, the cwd is containers so use paths relative to that i.e. ./ansible to access containers/ansible.

Use GIT_CONFIG_NOSYSTEM=1 when needed. You may need to add commit.gpgsign=false

Please read playbook_overview.md, todo.md, and borg-backup-cheatsheet.md in the same directory as AGENTS.md. Update both as the code base changes.