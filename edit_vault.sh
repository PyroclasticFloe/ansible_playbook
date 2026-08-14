#!/usr/bin/env bash
ansible-vault edit ~/containers/ansible/group_vars/all/vault.yml \
    --vault-password-file ~/private/ansible.vault

