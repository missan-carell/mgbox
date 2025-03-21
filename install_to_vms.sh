#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source $SCRIPT_DIR/utils.sh

mysql() {
    docker exec -t mgbox-database-1 mariadb -u mgbox -pmgbox mgbox ${OP:--NBe} "$@"
}

# Install Mgbox Agent to each VM
for vm in $(echo vm1 vm2 vm3 vm4); do
    install_token=$(mysql "SELECT install_token \
                           FROM device \
                           WHERE device_name='$vm'")

    install_token=$(echo "$install_token" | tr -d '\r\n')
    install_command="curl 'https://mgbox/install?install_token=$install_token' | bash -"

    lognote "Install to $vm: $install_command"
    docker exec -t mgbox-$vm-1 bash -c "$install_command"
done
