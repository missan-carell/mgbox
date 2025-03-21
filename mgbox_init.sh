#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source $SCRIPT_DIR/utils.sh

# Always save script output to log file
LOG_FILE=/var/log/mgbox_init.log
exec > >(tee -a $LOG_FILE) 2>&1

# Using the original mysql command
unset -f mysql

# Let mgbox logfile writable
touch $MGBOX_LOG_FILE
chmod a+rwx $MGBOX_LOG_FILE

# Setup database and account
cat > /etc/my.cnf <<EOF
[client]
    user = mgbox
    password = mgbox
    host = database 
    port = 3306
    database = mgbox
EOF

# Wait for database startup done
lognote "Wait for database up ..."
for i in $(seq 60); do
    mysql -e "show databases" | grep "mgbox"
    [ $? = 0 ] && lognote "Database ready!" && break
    sleep 1;
done

# Initialize `mgbox` database
lognote "Initialize mgbox database ..."
if mysql -e "show tables" | grep "device_user" > /dev/null 2>&1; then
  logwarn "mgbox database been initialized."
else
  mysql -u root -proot -h database <<'EOF'
    -- Create new database
    CREATE DATABASE IF NOT EXISTS `mgbox`;
    USE `mgbox`;

    -- Create account and Grant access
    -- DROP USER 'mgbox'@'%';
    -- CREATE USER 'mgbox'@'%' IDENTIFIED BY 'mgbox';
    -- GRANT ALL PRIVILEGES ON mgbox.* TO 'mgbox'@'%';
    -- FLUSH PRIVILEGES;

    CREATE TABLE IF NOT EXISTS `user` (
        `userid` INT AUTO_INCREMENT PRIMARY KEY,
        `username` VARCHAR(50) NOT NULL UNIQUE,
        `password_hash` CHAR(128) NOT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        `last_modified` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Add Test users
    INSERT IGNORE INTO `user` (username, password_hash) VALUES ('admin', SHA2('admin', 256));
    INSERT IGNORE INTO `user` (username, password_hash) VALUES ('test1', SHA2('test1', 256));
    INSERT IGNORE INTO `user` (username, password_hash) VALUES ('test2', SHA2('test2', 256));

    -- Retrieval userid of tester1 and tester2
    SELECT @userid_tester1 := userid FROM user where username='test1';
    SELECT @userid_tester2 := userid FROM user where username='test2';

    CREATE TABLE IF NOT EXISTS `device` (
        `userid` INT NOT NULL,
        `device_id` INT AUTO_INCREMENT PRIMARY KEY,
        `device_name` VARCHAR(50) NOT NULL,
        `access_token` VARCHAR(24) NOT NULL DEFAULT TO_BASE64(LEFT(SHA2(UUID(), 256), 12)),
        `install_token` VARCHAR(24) NOT NULL DEFAULT TO_BASE64(LEFT(SHA2(UUID(), 256), 12)),
        `description` VARCHAR(128) NOT NULL DEFAULT "",
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        `last_modified` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (`userid`) REFERENCES user(`userid`) ON DELETE CASCADE,
        UNIQUE (`userid`, `device_name`)
    );

    INSERT IGNORE INTO `device` (userid, device_name, description) VALUES (@userid_tester1, 'vm1', "DC shanghai");
    INSERT IGNORE INTO `device` (userid, device_name, description) VALUES (@userid_tester1, 'vm2', "DC Hangzhou");
    INSERT IGNORE INTO `device` (userid, device_name, description) VALUES (@userid_tester2, 'vm3', "DC shanghai");
    INSERT IGNORE INTO `device` (userid, device_name, description) VALUES (@userid_tester2, 'vm4', "DC Hangzhou");

    CREATE TABLE IF NOT EXISTS `device_connect_state` (
        `device_id` INT NOT NULL,
        `client_ip` CHAR(40) NOT NULL UNIQUE,
        `last_access` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (`device_id`) REFERENCES device(`device_id`) ON DELETE CASCADE,
        PRIMARY KEY (`device_id`, `client_ip`)
    );

    -- Retrieval device_id of tester1 and tester2
    SELECT @device_id_tester1_vm1 := device_id FROM device where userid=@userid_tester1 AND device_name='vm1';
    SELECT @device_id_tester2_vm3 := device_id FROM device where userid=@userid_tester2 AND device_name='vm3';

    CREATE TABLE IF NOT EXISTS `device_user` (
        `device_id` INT NOT NULL,
        `device_userid` INT AUTO_INCREMENT PRIMARY KEY,
        `device_user` VARCHAR(50) NOT NULL,
        `description` VARCHAR(128) NOT NULL DEFAULT "",
        `passtext` CHAR(128) NOT NULL DEFAULT 
            INSERT(TO_BASE64(LEFT(SHA2(UUID(), 256), 12)), \
                   FLOOR(0 + RAND() * 12), 1, \
                   SUBSTR('[!@#$%^&*()]', FLOOR(0 + RAND() * 12), 1)),
        `last_passtext` CHAR(128) NOT NULL DEFAULT '',
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        `last_modified` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (`device_id`) REFERENCES device(`device_id`) ON DELETE CASCADE,
        UNIQUE (`device_id`, `device_user`)
    );

    INSERT IGNORE INTO `device_user` (device_id, device_user, description) VALUES (@device_id_tester1_vm1, 'lihao', "DC shanghai");
    INSERT IGNORE INTO `device_user` (device_id, device_user, description) VALUES (@device_id_tester1_vm1, 'missan', "DC Hangzhou");
    INSERT IGNORE INTO `device_user` (device_id, device_user, description) VALUES (@device_id_tester2_vm3, 'lihao', "DC shanghai");
    INSERT IGNORE INTO `device_user` (device_id, device_user, description) VALUES (@device_id_tester2_vm3, 'missan', "DC Hangzhou");

    -- Create Views
    CREATE VIEW `user_device_view` AS 
        SELECT user.userid, user.username, device.device_id, device.device_name, device.access_token, \
               device.install_token, device.description, device.created_at, device.last_modified 
        FROM `user` INNER JOIN `device` ON user.userid = device.userid;

    CREATE VIEW `device_device_user_view` AS 
        SELECT device.userid, device.device_id, device.device_name, device_user.device_user, device_user.passtext,
               device_user.description, device_user.created_at, device_user.last_modified 
        FROM `device` LEFT JOIN `device_user` ON device.device_id = device_user.device_id;

    CREATE VIEW `user_device_device_user_view` AS 
        SELECT user.username, device_device_user_view.device_name, device_device_user_view.device_user, device_device_user_view.passtext,
               device_device_user_view.description, device_device_user_view.created_at, device_device_user_view.last_modified 
        FROM `device_device_user_view` LEFT JOIN `user` ON device_device_user_view.userid = user.userid;

    CREATE VIEW `user_device_connect_state_view` AS 
        SELECT user_device_view.username, user_device_view.device_name, device_connect_state.client_ip,
                device_connect_state.last_access, user_device_view.description
        FROM `user_device_view` LEFT JOIN `device_connect_state`
                ON user_device_view.device_id = device_connect_state.device_id;

    -- Create Indexes 
    CREATE UNIQUE INDEX `device_index` ON `device` (`userid`, `device_name`);
    CREATE UNIQUE INDEX `device_user_index` ON `device_user` (`device_id`, `device_user`);
EOF
  [ $? != 0 ] && logerr "Prepare database failed." && exit 1
fi

# Create and start mgbox service
# It provides HTTP/HTTPs service for remote clients.
lognote "Initialize mgbox http service ..."
MGBOX_SERVICE='/etc/systemd/system/mgbox.service'
[ ! -f $MGBOX_SERVICE ] && cat > $MGBOX_SERVICE <<'EOF'
    [Unit]
    Description=mgbox server daemon
    Documentation=
    After=network.target
    Wants=

    [Service]
    Type=simple
    EnvironmentFile=
    ExecStart=/usr/mgbox/mgbox_server.sh --port 443
    ExecReload=/bin/kill -HUP $MAINPID
    ExecStop=/bin/kill -TERM $MAINPID
    KillMode=process
    Restart=on-failure
    RestartSec=10s

    [Install]
    WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable mgbox
systemctl start mgbox


# Allow HTTP and HTTPS services on firewall
lognote "Initialize firewall ..."
firewall-cmd --permanent --add-service http
firewall-cmd --permanent --add-service https
firewall-cmd --reload

lognote "Initialize mgbox done."
