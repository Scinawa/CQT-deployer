#!/bin/bash
ansible-playbook -i inventory/hosts.yml --ask-vault-pass playbooks/cqt-reporting.yml 