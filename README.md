# pf9-upgrade

The tools here can be used to upgrade an environment from Ubuntu 14.04 LTS to Ubuntu 16.04 LTS.

Only the bare minimum is handled by Ansible playbooks.

Syntax:
```
ansible-playbook -i inventory/hosts upgrade-hosts.yml --limit <host>
```

## Prerequisites

- You must be running 14.04 LTS or 16.04 LTS. No intermediate versions allowed.
- All instances on a given host must be shutdown. The tasks will not run if instances are running.

## Process

The following is executed (high level):

### Phase 1

- System is upgraded to latest 14.04 release (apt update / apt dist-upgrade)
- System is rebooted automatically (if necessary).
- A 'do-release-upgrade' to upgrade from 14.04 -> 16.04 is executed
- *User is prompted to reboot*. Xenial tasks will not run without a reboot.

### Phase 2

- Packages are refreshed (apt update / apt dist-upgrade)
- Services are converted from init to systemd
- libvirt-bin is tweaked (remove -d flag)
- openssl packages are replaced
- Packages are cleaned up
- System is rebooted automatically (if necessary)
