#!/usr/bin/bash

setup_mgbox_client_service() {
    lognote "Setting up mgbox client service ..."
    MGBOXC_SERVICE='/etc/systemd/system/mgboxc.service'
    [ ! -f $MGBOXC_SERVICE ] && cat > $MGBOXC_SERVICE <<'EOF'
[Unit]
Description=mgbox client daemon
Documentation=
After=network.target
Wants=

[Service]
Type=simple
EnvironmentFile=
ExecStart=/usr/mgbox/mgbox_client.sh
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -TERM $MAINPID
KillMode=process
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable mgboxc
    systemctl restart mgboxc
}

setup_sanity_check() {
    lognote "Checking sanity ..."

    # Check target OS: Ubuntu
    if ! $(cat /etc/issue | grep "Ubuntu" > /dev/null 2>&1); then
        logerr "Only Ubuntu is supported."
        exit 0
    fi

    # Check systemd installed
    if ! $(which systemctl > /dev/null 2>&1); then
        logerr "Systemd not found."
        exit 0
    fi

    # Check systemd is running
    if ! $(ps -elf | grep "/sbin/init" > /dev/null 2>&1); then
        logerr "Systemd is not running."
        exit 0
    fi
}

main() {
    setup_sanity_check || fatal "Sanity check failed."
    mgbox_client_config || fatal "mgbox client config failed."
    setup_mgbox_client_script || fatal "mgbox client script failed."
    setup_mgbox_client_service || fatal "mgbox client service failed."
    lognote "mgbox client setup done."
}

main "$@"
