#!/bin/bash

ubuntu14_16_upgrade() {

    echo "CHECKING IF SCRIPT IS RUN AS ROOT
    ============="

    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Exiting..."
        exit
    fi

    echo "RELEASE AND VERSION CHECKS
    =============
    If the detected operating system is not Ubuntu 14.04 or Ubuntu 16.04
    this script will not run."

    local os=$(lsb_release -i | awk '{print $3}')
    local version=$(lsb_release -r | awk '{print $2}')

    echo "
    Checking OS
    ------------
    "

    if [ "$os" = "Ubuntu" ]; then
        echo OS is Ubuntu. Progressing...
    else
        echo OS is not Ubuntu. Upgrade script should not be run here. Exiting...
        exit
    fi

    echo "
    Checking OS version
    ------------
    "

    if [ $version = 14.04 ]; then
        echo OS version is 14.04.
        u14_update_upgrade
    else
        if [ $version = 16.04 ]; then
            echo OS version is 16.04.
            u16_upgrade_path
        else
            echo OS version is not 14.04 or 16.04. Exiting...
            exit
        fi
    fi
}

general_node_prechecks() {

    echo "
    GENERAL PRECHECKS
    =============
    - Check that there are no instances running.
    - Check that pf9-hostagent is installed."

    echo "
    Checking PF9 hostagent
    ------------
    "

    apt-cache policy pf9-hostagent
    local hostagent_installed=$(dpkg -l pf9-hostagent | awk '/ii/ {print $1}')
    if [ "$hostagent_installed" = "ii" ]; then
        echo Node appears to be a PF9 managed node. Continuing...
    else
        echo Node does not appear to be a PF9 managed node or there is something wrong with pf9-hostagent. Exiting...
        exit
    fi

    echo "
    Checking for running VMs
    ------------
    "

    virsh list 2>/dev/null
    local vm_count=$(virsh list 2>/dev/null | grep -c running)
    if [[ $vm_count > 0 ]]; then
        echo $vm_count instances running. Exiting...
        exit
    else
        echo $vm_count instances running. Continuing...
    fi

    echo "General prechecks completed..."
}

u14_update_upgrade() {
    general_node_prechecks

    echo "
    UBUNTU 14.04 UPDATES
    =============
    - Performing update, upgrade, dist-upgrade and update-manager-core
    "

    apt-get update
    local up=$(apt-get -y upgrade | tail -n 1 | awk -F',' '/0 upgraded/ {print $1}')
    local dup=$(apt-get -y dist-upgrade | tail -n 1 | awk -F',' '/0 upgraded/ {print $1}')
    local umc=$(apt-get -y install update-manager-core | tail -n 1 | awk -F',' '/0 upgraded/ {print $1}')

    echo "
    Reviews package upgrades and reboot if necessary
    ------------
    "

    if [[ "$up" != "0 upgraded" ]]; then
        echo Packages were upgraded. Rebooting...
        echo Perform general validatation checks after reboot before proceeding.
        reboot
    else
        if [[ "$dup" != "0 upgraded" ]]; then
            echo Packages were upgraded. Rebooting...
            echo Perform general validatation checks after reboot before proceeding.
            reboot
        else
            if [[ "$umc" != "0 upgraded" ]]; then
                echo Packages were upgraded. Rebooting...
                echo Perform general validatation checks after reboot before proceeding.
                reboot
            else
                echo No packages were upgraded. Proceed with do-release-upgrade.
            fi
        fi
    fi
}

u16_upgrade_path() {
    general_node_prechecks
    init_systemd
    d_libvirt-bin_remove
    remove_python-openssl
    upgrade_python-apt
    install_haproxy
    echo "Review logging and then reboot host to complete."
#    reboot
}

init_systemd() {

    echo "
    REMOVING init.d FILES
    =============
    - remove pf9-comms pf9-hostagent pf9-novncproxy pf9-ostackhost pf9-sidekick
    init.d files
    - create unit files
    "

    init_file_count=0
    for i in pf9-comms pf9-hostagent pf9-novncproxy pf9-ostackhost pf9-sidekick; do
        if [[ -e /etc/init.d/$i ]]; then
            let "init_file_count+=1";
        fi ;
    done

    if [[ $init_file_count > 0 ]]; then
        echo $init_file_count init.d scripts found that should not exist
    else
        echo $init_file_count init.d scripts found. Assuming script has been run before. Exiting...
        exit
    fi

    # Since these services no longer run under init we have to modify these accordingly

    for i in pf9-comms pf9-hostagent pf9-novncproxy pf9-ostackhost pf9-sidekick; do mv /etc/init.d/$i ~/; done

    # Create unit files

    echo "
    Creating unit files
    ------------
    /lib/systemd/system/pf9-comms.service
    /lib/systemd/system/pf9-hostagent.service
    /lib/systemd/system/pf9-sidekick.service
    /lib/systemd/system/pf9-novncproxy.service
    /lib/systemd/system/pf9-ostackhost.service
    "

echo "[Unit]
Description=Platform9 Communications Service
ConditionPathExists=/opt/pf9/comms/pf9-comms.js
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/pf9/pf9-comms.env
ExecStartPre=/bin/mkdir -p /var/log/pf9/comms
ExecStart=/bin/bash -c '/opt/pf9/comms/pf9-comms.js >> /var/log/pf9/comms/comms-stdout.log 2>&1'
PIDFile=/var/run/pf9-comms.pid
Restart=on-failure
User=pf9
Group=pf9group
RestartSec=30

[Install]
Alias=pf9-comms

[Install]
WantedBy=multi-user.target" > /lib/systemd/system/pf9-comms.service

echo "[Unit]
Description=Platform9 Host Agent Service
ConditionPathExists=/opt/pf9/hostagent/bin/pf9-hostd
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/pf9/hostagent/pf9-hostagent.env
ExecStartPre=/opt/pf9/hostagent/pf9-hostagent-prestart.sh
PermissionsStartOnly=true
ExecStart=/bin/bash -c '/opt/pf9/hostagent/bin/pf9-hostd >> /var/log/pf9/hostagent-daemon.log 2>&1'
PIDFile=/var/run/pf9-hostagent.pid
Restart=always
User=pf9
Group=pf9group
RestartSec=30
StartLimitIntervalSec=600
StartLimitBurst=6
RestartPreventExitStatus=0

[Install]
Alias=pf9-hostd

[Install]
WantedBy=multi-user.target" > /lib/systemd/system/pf9-hostagent.service

echo "[Unit]
Description=Platform9 Sidekick Service
ConditionPathExists=/opt/pf9/sidekick/pf9-sidekick.js
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/pf9/pf9-sidekick.env
ExecStartPre=/bin/mkdir -p /var/log/pf9/sidekick
ExecStart=/bin/bash -c '/opt/pf9/sidekick/pf9-sidekick.js >> /var/log/pf9/sidekick/sidekick-stdout.log 2>&1'
PIDFile=/var/run/pf9-sidekick.pid
Restart=on-failure
User=pf9
Group=pf9group
RestartSec=10

[Install]
Alias=pf9-sidekick

[Install]
WantedBy=multi-user.target" > /lib/systemd/system/pf9-sidekick.service


echo "[Unit]
Description=Platform9 OpenStack noVNC proxy service
ConditionPathExists=/opt/pf9/venv/bin/pf9-novncproxy

[Service]
Type=simple
EnvironmentFile=/opt/pf9/venv/nova.env
ExecStart=/opt/pf9/venv/bin/pf9-novncproxy --config-dir /opt/pf9/etc/nova/conf.d --web /opt/pf9/novnc --log-file /var/log/pf9/novncproxy.log
PIDFile=/var/run/pf9-novncproxy.pid
# To avoid log duplication in syslog and service log redirect stdout and stderr to null
StandardOutput=null
StandardError=null
# Service is monitored by pf9-hostagent service
Restart=no
User=pf9
Group=pf9group
RestartSec=30

[Install]
WantedBy=multi-user.target" > /lib/systemd/system/pf9-novncproxy.service

echo "[Unit]
Description=Platform9 OpenStack Compute service
ConditionPathExists=/opt/pf9/venv/bin/pf9-ostackhost
ConditionPathExists=/opt/pf9/venv/bin/pf9-nova-prestart-script.sh
Wants=dbus.service
Wants=libvirtd.service

[Service]
Type=simple
ExecStartPre=/opt/pf9/venv/bin/pf9-nova-prestart-script.sh
EnvironmentFile=/opt/pf9/venv/nova.env
PermissionsStartOnly=true
ExecStart=/opt/pf9/venv/bin/pf9-ostackhost --config-dir /opt/pf9/etc/nova/conf.d/ --log-file /var/log/pf9/ostackhost.log
PIDFile=/var/run/pf9-ostackhost.pid
# To avoid log duplication to syslog and service log redirect stdout and stderr to null
StandardOutput=null
StandardError=null
# Service monitored by pf9-hostagent service
Restart=no
User=pf9
Group=pf9group

[Install]
WantedBy=multi-user.target" > /lib/systemd/system/pf9-ostackhost.service

    # Enable pf9-comms pf9-hostagent to auto start

    for i in pf9-comms pf9-hostagent; do systemctl enable $i; done
}

d_libvirt-bin_remove() {
    echo "
    ENSURING -d FLAG IS REMOVED FROM libvirt-bin
    =============
    "
    # ensure -d flag is removed from libvirt-bin
    sed -i 's/libvirtd_opts="-d -l"/libvirtd_opts="-l"/g' /etc/default/libvirt-bin
}


remove_python-openssl () {
    # remove python-openssl
    echo "
    REMOVE python-ssl IF INSTALLED VIA PACKAGE MANAGER
    =============
    "
    echo Removing python-ssl if installed via package
    local installed=$(apt-cache policy python-openssl | awk '/Installed/ {print $2}')

    if [[ "$installed" = "(none)" ]]; then
        echo python-openssl not installed via apt.
    else
        echo Need to remove incompatible python-openssl
        apt remove -y --purge python-openssl
        apt install python-pip -y
        pip install pyopenssl
    fi
}

upgrade_python-apt() {
    echo "
    UPGRADE python-apt
    =============
    "
    echo Upgrading python-apt
    apt-get --only-upgrade install python-apt
}

install_haproxy() {
    echo "
    INSTALL haproxy FOR NEUTRON
    =============
    "
    apt-get update
    apt-get install -y haproxy=1.6.\*
}

ubuntu14_16_upgrade
