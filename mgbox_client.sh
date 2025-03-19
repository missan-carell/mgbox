#!/usr/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/utils.sh" ] && source $SCRIPT_DIR/utils.sh

parse_config() {
    MGBOXC_SCRIPT='/usr/mgbox/mgboxc.conf'
    if [ ! -f "$MGBOXC_SCRIPT" ]; then
        logerr "$MGBOXC_SCRIPT not found."
        exit 1
    fi

    SERVER_URL=$(cat $MGBOXC_SCRIPT | grep ^SERVER_URL= | cut -d '=' -f 2)
    USERNAME=$(cat $MGBOXC_SCRIPT | grep ^USERNAME= | cut -d '=' -f 2)
    DEVICE_NAME=$(cat $MGBOXC_SCRIPT | grep ^DEVICE_NAME= | cut -d '=' -f 2)
    ACCESS_TOKEN=$(cat $MGBOXC_SCRIPT | grep ^ACCESS_TOKEN= | cut -d '=' -f 2)

    MGBOX_SERVER_URL="$SERVER_URL/account?username=$USERNAME&device_name=$DEVICE_NAME"
    MGBOX_SERVER_URL="$MGBOX_SERVER_URL&access_token=$ACCESS_TOKEN"
    loginfo "MGBOX_SERVER_URL=$(echo \"$MGBOX_SERVER_URL\" | sed 's/access_token=.*\&/access_token=***\&/g')"
}

parse_http_response() {
    # The format of HTTP response is:
    # # HTTP/1.1 200 OK
    # # Context-Type: text/html
    # # X-Server: mgbox-http-server
    # # Connection: close
    # # 
    # # vm1	lihao	YmFi(jNkZTg4NDEw	1742089031
    # # vm1	missan	&DRmNzg2ZDk4Y2U2	1742089031
    # # ...
    loginfo "Parsing HTTP response..."

    local BLSTART=
    while read -r line; do
        # Trim the tailed '\r\n'
        line=$(echo $line | tr -d '\r\n')

        # Skip HTTP header: the lines before blank line
        if [ -z "$BLSTART" ]; then
            [ -z "$line" ] && BLSTART=true
            continue
        fi

        # Parse user data, the format is:
        # <device-name>	<username>	<passtext>	<lastmodify>
        read devicename username passtext lastmodify <<< "$line"
        loginfo "Device: $devicename, User: $username, LastModify: $lastmodify." 
        if [ -z "$lastmodify" ]; then 
            logerr "Bad data format: $line."; 
            continue
        fi

        # Validate username and passtext
        if ! valiate_name "username" "$username"; then
            logerr "Bad username: $username."
            continue
        fi
        if [ "${#passtext}" != 16 ]; then
            # passtext length must equal to 16
            logerr "Bad passtext format. "${#passtext}""
            continue
        fi

        # Add new user or change passwd for existing user
        cat /etc/passwd | grep -w "$username" > /dev/null 2>&1
        if [ ! $? = 0 ]; then
            lognote "Add new user $username ..."
            useradd -m -s /bin/bash -p "$passtext" "$username"
            continue
        fi

        # Change passwd for existing user
        loginfo "Changing passwd for user $username ..."
        echo -e "$passtext\n$passtext" | passwd "$username"
    done <<< "$1"
}

mgboxc_pull_account() {
    # Send http request to mgbox server
    lognote "mgboxc_pull_account ..."
    # MGBOX_SERVER_URL='https://mgbox/account?username=test1&access_token=YjgwZDJhMTU5MmZm&device_name=vm1'
    data="$(curl -is $MGBOX_SERVER_URL)"
    
    # Check http response header: 200 OK
    HEAER_LINE=$(echo "$data" | awk 'NR==1 {print $0}')
    loginfo "$HEAER_LINE"
    if [[ ! "$HEAER_LINE" =~ "200 OK" ]]; then
        logerr "Bad HTTP response: $data."
        continue
    fi

    # Parse http response
    parse_http_response "$data"
}

main() {
    # Pull account from mgbox server periodically
    while true; do
        parse_config || break

        # Pull account data from mgbox server
        mgboxc_pull_account

        # FIXME:
        sleep 10
    done
}

main "$@"
