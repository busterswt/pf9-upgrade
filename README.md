# pf9-upgrade

The tools here can be used to upgrade an environment from Ubuntu 14.04 LTS to Ubuntu 16.04 LTS.

Only the bare minimum is handled by Ansible playbooks.

Syntax:
```
ansible-playbook -i inventory/hosts upgrade-hosts.yml --limit <host>
```
