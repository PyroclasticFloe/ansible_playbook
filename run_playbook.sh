#/usr/bin/env bash
cd ~/containers/ansible
ansible-playbook -i inventory ./playbook.yml --vault-password-file ~/ansible.vault
cd -
