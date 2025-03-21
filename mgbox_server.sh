#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source $SCRIPT_DIR/utils.sh

auto_refresh_user_keys() {
  lognote "Starting task ..."
  
  KEY_REFSH_INTERVAL=300  # seconds
  while true; do
    # Set KEY_REFSH_INTERVAL to 60 seconds if less than 60 seconds
    [[ "KEY_REFSH_INTERVAL" -lt 60 ]] && KEY_REFSH_INTERVAL=60
    
    # Auto refresh user keys
    for ((i=1; ; i++)); do
      sleep $KEY_REFSH_INTERVAL
      loginfo "refresh user keys (inteval: $KEY_REFSH_INTERVAL, times $i) ..."
      mysql_exec "UPDATE device_user SET passtext=\
                      INSERT(TO_BASE64(LEFT(SHA2(UUID(), 256), 12)), \
                      FLOOR(0 + RAND() * 12), 1, \
                      SUBSTR('[!@#$%^&*()]', FLOOR(0 + RAND() * 12), 1))"
      # mysql_exec "UPDATE device SET install_token=\
      #                 TO_BASE64(LEFT(SHA2(UUID(), 256), 12))"
      if [ $? = 0 ]; then
        lognote "Auto refresh user keys success!"
      fi
    done

    # Unexpected broken: restart task after 1 second
    loginfo "Unexpected broken: restart task after 1 second ..."
    sleep 1;
  done
}

# @ [URI]
check_request_uri() {
  ALLOWED_URI=(/account /install /uninstall /cert/ca)
  for uri in "${ALLOWED_URI[@]}"; do
    [ "$1" == "$uri" ] && return 0
  done
  return 1
}

mgbox_req_install_and_account() {
  # Parse query
  local REQ_QUERYS="$(tr '&' '\n' <<< $REQ_QUERY)"
  while read line; do
    case "$line" in
      username=*)
        username=${line:9};;
      install_token=*)
        install_token=${line:14};;
      access_token=*)
        access_token=${line:13};;
      device_name=*)
        device_name=${line:12};;
      last_modify=*)
        last_modify=${line:12};;
      *)
        echo Bad query: $line;;
    esac
  done <<< "$REQ_QUERYS"
  
  # Query device_user information from database by install_token
  if [ "$REQ_URI" = "/install" -a -n "$install_token" ]; then
    lognote "Query device_user information by install_token $install_token ..."
    data=$(mysql "SELECT username, device_name, access_token \
                  FROM user_device_view WHERE install_token='$install_token'");
    if [[ -z "$data" && "$data" =~ failed|rror ]]; then
        logerr "Query device_user information error(install_token $install_token): $data"
        http_resp_400 "Bad install_token"
        return 1
    fi

    # Parse device_user information
    read -r username device_name access_token <<< "$data"
    if [ ! $? -o -z "$access_token" ]; then
        logerr "Parse device_user information error: $data"
      http_resp_400 "Bad install_token"
      return 1
    fi
  else
    # Verify input parameters
    [ -z "$username" ] && http_resp_400 "Username is empty" && return 1
    [ -z "$access_token" ] && http_resp_400 "access_token is empty" && return 1
    [ -z "$device_name" ] && http_resp_400 "device_name is empty" && return 1

    # Verify user login account
    loginfo "username: $username, device_name: $device_name access_token: '$access_token'"
    # data=$(mysql "SELECT username FROM user_device_view \
    #               WHERE username='$username' AND device_name='$device_name'");
    data=$(mysql "SELECT username FROM user_device_view \
                  WHERE username='$username' AND device_name='$device_name' AND access_token='$access_token';");
    if [ ! "$username" = "$data" ]; then
      http_resp_400 "Bad username or access_token"
      return 1
    fi
  fi

  if [ "$REQ_URI" = "/install" ]; then
    lognote "install: $username, device_name: $device_name '$access_token'"

    # Query device_user information from database
    # data=$(mysql "SELECT device_name, device_user, passtext, UNIX_TIMESTAMP(last_modified) \
    #                 FROM user_device_device_user_view \
    #                 WHERE username='$username' AND device_name='$device_name';");
    data="$(
      cat $SCRIPT_DIR/utils.sh

      # Make mgbox_client_config
      cat <<'EOF'
mgbox_client_config() {
  lognote "Setting up mgbox client config ..."
  MGBOXC_SCRIPT='/usr/mgbox/mgboxc.conf'
  [ ! -d "/usr/mgbox" ] && mkdir -p /usr/mgbox && chmod 600 /usr/mgbox
  cat > $MGBOXC_SCRIPT <<SETUP_EOF
EOF
      cat <<EOF
# mgbox client config
SERVER_URL=${SERVER_URL:-https://mgbox}
USERNAME=$username
DEVICE_NAME=$device_name
ACCESS_TOKEN=$access_token
SETUP_EOF
  return 0
}
EOF

      # Make client script
      cat <<'EOF'
setup_mgbox_client_script() {
  lognote "Setting up mgbox client script ..."
  MGBOXC_SCRIPT='/usr/mgbox/mgbox_client.sh'
  cat > $MGBOXC_SCRIPT <<'SETUP_EOF'
EOF
      cat $SCRIPT_DIR/utils.sh
      cat $SCRIPT_DIR/mgbox_client.sh
      cat <<'EOF'
SETUP_EOF
  chmod a+x "/usr/mgbox/mgbox_client.sh"
  return 0
}
EOF
      # Make mgbox_setup
      cat $SCRIPT_DIR/mgbox_client_setup.sh
    )"
  else
    # Fetch device_id
    data=$(mysql "SELECT device_id FROM user_device_view \
                    WHERE username='$username' AND device_name='$device_name'");
    if [[ -z "$data" || "$data" =~ failed|rror ]]; then
        logerr "'$name' get device_id failed: $data"
        http_resp_500 "query device_id error"
        return 1
    fi
    device_id="$data"

    # Update state
    client_ip=$(netstat -natp | grep "$PPID/nc" | awk '{print $5}' | awk -F: '{print $1}')
    client_ip="${client_ip:-unknown}"
    mysql_exec "REPLACE INTO device_connect_state(device_id, client_ip, last_access) \
                VALUES ('$device_id', '$client_ip', CURRENT_TIMESTAMP)";
    if [ $? = 0 ]; then
      loginfo "update device 'username='$username':$device_name'(client_ip=$client_ip) connect_state success!"
    fi

    # Query device_user information from database
    data=$(mysql "SELECT device_name, device_user, passtext, UNIX_TIMESTAMP(last_modified) \
                    FROM user_device_device_user_view \
                    WHERE username='$username' AND device_name='$device_name'");
    if [[ "$data" =~ failed|rror ]]; then
        logerr "'$name' pull_keys failed: $data"
        http_resp_500 "query database error"
        return 1
    fi
  fi

  # Send http response
  http_resp_200 "$data"
}

mgbox_req_mgboxc_uninstall() {
data=$(cat <<EOF
  # uninstall services 
  systemctl daemon-reload
  systemctl disable mgboxc
  systemctl stop mgboxc
  rm -f /etc/systemd/system/mgboxc.service
  rm -f /usr/mgbox/mgbox_client.sh
  rm -f /usr/mgbox/ca.crt

  echo "Mgbox stop done!"
  echo "Please manualy remove below files:"
  echo "  rm -rf /usr/mgbox/"
  echo "  rm -f /var/log/mgbox.log"
EOF
)
  # Send http response
  http_resp_200 "$data"
}

handle_http_request() {
  loginfo "handle_http_request: $REQ_URI"
  if ! check_request_uri "$REQ_URI"; then
    http_resp_400 "Bad Request URI"
    return 1
  fi

  case $REQ_URI in
    /cert/ca)
      # response
      http_resp_200 "$(cat /usr/mgbox/ca.crt)"
      ;;
    /uninstall)
      mgbox_req_mgboxc_uninstall
      ;;
    /install | /account)
      mgbox_req_install_and_account
      ;;
    *)
      return http_resp_400 "Bad Request URI"
      ;;
  esac
}

##########################################################################
# HTTP Server 
##########################################################################

REQ_URI=
REQ_QUERY=
http_recv() {
  # Receive & parse http header
  local DLEN=
  while read -t 1 line; do
  line=$(echo $line | tr -d '\r\n')
  
  # Parse http header-line
  if [ -z $REQ_URI ]; then
    lognote "HTTP: $(echo \"$line\" | sed 's/access_token=.*\&/access_token=***\&/g')"
    URL=$(echo "$line" | awk '{ match($0, /^(GET|POST) (.*) HTTP\/1\.1$/, arr); print arr[2];}')
    [ -z $URL ] && logerr "Bad Request: $line" && return 1
  
    REQ_URI=${URL%\?*}
    [[ "$URL" =~ \? ]] && REQ_QUERY=${URL#*\?}
  
    loginfo "REQ_URI: $REQ_URI"
    loginfo "REQ_QUERY: $(echo \"$REQ_QUERY\" | sed 's/access_token=.*\&/access_token=***\&/g')"
  else
    loginfo "HTTP: $line"
    [ -z "$line" ] && break
  fi
  done
}

http_resp() {
  loginfo "HTTP response status: HTTP/1.1 $1"

  # Convert HTTP Header: '\n' to '\r\n'
  # CAUTION: DO NOT CHANGE THE FORMAT OF THE FOLLOWING CODE.
  sed 's/$/\r/g' <<EOF
HTTP/1.1 $1
Context-Type: text/html
X-Server: mgbox-http-server
Connection: close

EOF
echo "$2"
}

http_resp_200() { http_resp "200 OK" "$1"; }
http_resp_400() { http_resp "400 Bad Request" "$1"; }
http_resp_500() { http_resp "500 Internal error" "$1"; }

main() {
  if [ "$1" = "--port" ]; then
    # Handle signals: Kill all child processeson exit
    trap 'kill $(jobs -p); lognote "server exting..."; exit 1' SIGINT SIGTERM EXIT

    # Start auto-refresh-user-keys task
    lognote "Start auto-refresh-user-keys task ..."
    auto_refresh_user_keys &

    # Start http server
    lognote "Start http server on port $2"
    while true; do
      # Start https server
      local OPTION="--ssl --ssl-cert=/usr/mgbox/mgbox.crt --ssl-key=/usr/mgbox/mgbox.key"
      nc $OPTION -klp ${2:-7180} -e $0
      sleep 0.1
    done
  else
    # Run as CGI to handle http request
    http_recv || ( logerr "Error: http_recv error!" && exit 1 )
    [ -n "$REQ_URI" ] && handle_http_request
  fi
}

main "$@"
