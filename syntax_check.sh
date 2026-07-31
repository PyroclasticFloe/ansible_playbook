#!/usr/bin/env bash
cd ~/containers/ansible
ansible-playbook -i inventory ./playbook.yml --syntax-check --vault-password-file ~/ansible.vault
cd -
