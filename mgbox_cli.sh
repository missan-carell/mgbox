#!/bin/bash
# Version: v1.0
# Author: lihao@lida
# Description: MGBOX CLI

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source $SCRIPT_DIR/utils.sh

TITLE=$(cat <<'EOF'
   __       __   ______    ______   ______   ______         _______    ______   __    __ 
  /  \     /  | /      \  /      \ /      | /      \       /       \  /      \ /  |  /  |
  $$  \   /$$ |/$$$$$$  |/$$$$$$  |$$$$$$/ /$$$$$$  |      $$$$$$$  |/$$$$$$  |$$ |  $$ |
  $$$  \ /$$$ |$$ |__$$ |$$ | _$$/   $$ |  $$ |  $$/       $$ |__$$ |$$ |  $$ |$$  \/$$/ 
  $$$$  /$$$$ |$$    $$ |$$ |/    |  $$ |  $$ |            $$    $$< $$ |  $$ | $$  $$<  
  $$ $$ $$/$$ |$$$$$$$$ |$$ |$$$$ |  $$ |  $$ |   __       $$$$$$$  |$$ |  $$ |  $$$$  \ 
  $$ |$$$/ $$ |$$ |  $$ |$$ \__$$ | _$$ |_ $$ \__/  |      $$ |__$$ |$$ \__$$ | $$ /$$  |
  $$ | $/  $$ |$$ |  $$ |$$    $$/ / $$   |$$    $$/       $$    $$/ $$    $$/ $$ |  $$ |
  $$/      $$/ $$/   $$/  $$$$$$/  $$$$$$/  $$$$$$/        $$$$$$$/   $$$$$$/  $$/   $$/ 

EOF
)

trap "" SIGINT
CURRENT_USER=

# @ username password
login_check_password() {
  data=$(mysql "select username FROM user WHERE username = '$1' AND password_hash = SHA2('$2', 256)");
  if [[ "$data" =~ failed|rror ]]; then
    logerr "check user '$1' failed: $data"
  else
    data=$(echo "$data" | awk '{print $1}')    
    if [ -n "$1" -a "$data" = "$1" ]; then
      [ $? ] && return 0
    fi
  fi
  return 1
}


mgbox_login() {
#  CURRENT_USER=test1
#  return 0
  while true; do
    # Prevent brute force password attacks 
    while true; do read -t 1 cmd || break; done
    clear

    echo -e "$TITLE\n\n  $(green MAGIC KEY BOX) by lihao@lidai\n"
    read -s -p "Press $(green Enter) key to login system" cmd
    echo
    [ "$cmd" = "quit" ] && return 1

    # Login to system
    for i in $(seq 3); do
      read -t 20 -p "Username: " username || break 
      read -t 20 -p "Password: " -s passwd || break 
      echo

      login_check_password $username $passwd
      if [ $? = 0 ]; then
        CURRENT_USER=$username
        echo "Welcome $username, login success!" && return 0
      else
        logerr "Bad username or password!"
      fi
    done
  done
}

# @ opcode
menu_exit() {
  local _op=$op && op=                             # clear op
  [ "$_op" = "x" ] && return 254                 # Exit current menu
  [[ "$_op" = "X"  ||  $? = 255 ]] && return 255 # Exit CLI
  return 0
}

# @ Get a char from given charset
# @ [allowed charset]
getop() {
    while true; do
      # Read one charactor for keyboard.
      read -t 300 -n 1 -s op || return ?
      [[ "$op" =~ [0-9a-zA-Z] ]] && echo -ne "${op}\b"
      
      # Operation exists range, break.
      [[ "$op" =~ $1 ]] && echo && break;
    done
    return 0
}

getop_from_menu() {
  # Show menu & get a char from charset
  echo -ne "\n${1}\nChoose your Operation: "
  charset=$(awk '/^\s*[0-9a-zA-Z]\..*/ {printf $1}' <<< ${1} | sed 's/\.//g')
  getop "[$charset]" || return $?;

  local operation=$(grep " ${op}. " <<< "${1}")
  lognote "User '$CURRENT_USER' operation:" $operation
  echo
}

enter_admin_system() {
  while true; do
    # Choose an operation from menu
    getop_from_menu "$(cat <<EOF
=== MGBOX $(green Administrator) System ===
Operation Menu:
  1. List user
  2. Add new user
  3. Modify user password
  4. Delete user
  5. List all device
  6. Show logging
  7. Show startup logging
  x. Exit admin
  X. Exit system
EOF
)" || return $?

    # Handle operation:
    if [ "$op" == "1" ]; then       # List user
      data=$(OP=-te mysql "select username, created_at from user");
      if [[ "$data" =~ failed|rror ]]; then
        logerr "List user '$username' failed: $data"
      else
        echo "$data"
      fi

    elif [ "$op" = "2" ]; then      # Add new user
      read -t 30 -p "Username: " username || continue 
      read -t 30 -p "Password: " -s passwd || continue 
      echo

      valiate_name "username" "$username" ||  continue
      [ -z "$passwd" ] && logwarn "Password must not be blank!" && continue

      # Confirm Add?
      read -t 30 -p "Are your add new user: $username? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "INSERT INTO user (username, password_hash) VALUES ('$username', SHA2('$passwd', 256));";
      if [ $? = 0 ]; then
        lognote "Add user '$username' success!"
      fi

    elif [ "$op" == "3" ]; then     # Modify user password
      read -t 30 -p "Username: " username || continue
      read -t 30 -p "Password: " -s new_passwd || continue 
      echo
      read -t 30 -p "Confirm password: " -s confirm_passwd || continue 
      echo

      [ -z "$username" ] && logwarn "Username must not be blank!" && continue
      [ -z "$new_passwd" ] && logwarn "Password must not be blank!" && continue
      [ "$confirm_passwd" != "$new_passwd" ] && logwarn "Confirm password !" && continue

      # Confirm Modify user password?
      read -t 30 -p "Are your sure modify password: $username? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "UPDATE user set password_hash=SHA2('$new_passwd', 256), last_modified=CURRENT_TIMESTAMP \
                  WHERE username='$username'";
      if [ $? = 0 ]; then
        lognote "Modify user '$username' password success!"
      fi

    elif [ "$op" == "4" ]; then     # Delete user
      read -t 30 -p "Username: " username || continue
      valiate_name "username" "$username" ||  continue
      [ "$username" = "admin" ] && logwarn "Cann't delete user admin" && continue

      # Confirm Delete?
      read -t 30 -p "Are your delete user '$username' and his devices? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "delete from user where username='$username'"
      if [ $? = 0 ]; then
        lognote "Delete user '$username' success!"
      fi

    elif [ "$op" == "5" ]; then       # List all device
      ids="username, device_name, install_token, created_at, last_modified, description"
      data=$(OP=-te mysql "SELECT $ids FROM user_device_view");
      if [[ "$data" =~ failed|rror ]]; then
        logerr "List device failed: $data"
      else
        echo "$data"
      fi

    elif [ "$op" == "6" ]; then       # Show logging
      tail -n 1000 "/var/log/mgbox.log"

    elif [ "$op" == "7" ]; then       # Show startup logging
      tail -n 1000 "/var/log/mgbox_init.log"

    else
      # Exit menu
      menu_exit || return $?
    fi
  done
}

enter_clinet_device_user_management() {
  while true; do
    # Choose an operation from menu
    getop_from_menu "$(cat <<EOF
=== MGBOX Client Managerment :: $(green Devices User Managerment) System ===
User: $CURRENT_USER  Device: $CURRENT_DEVICE
Operation Menu:
  1. List device user
  2. Add new device user
  3. Update device user infomation
  4. Delete device user
  5. Refresh device user password
  x. Exit sub menu
EOF
)" || return $?

    # Handle operation:
    if [ "$op" == "1" ]; then       # List device user
      ids="device_name, device_user, passtext, created_at, last_modified, description"
      data=$(OP=-te mysql "SELECT $ids FROM user_device_device_user_view \
                           WHERE username='$CURRENT_USER' and device_name='$CURRENT_DEVICE'");
      if [[ "$data" =~ failed|rror ]]; then
        logerr "List device user failed: $data"
      else
        echo "$data"
      fi

    elif [ "$op" = "2" ]; then      # Add device new user
      read -t 30 -p "Device user name: " device_user || continue 
      read -t 30 -p "Description: " description || continue 

      valiate_name "device user name" "$device_user" ||  continue
      [ -z "$description" ] && logwarn "Description must not be blank!" && continue

      # Confirm Add?
      read -t 30 -p "Are your add new device user: $device_user? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "INSERT INTO device_user (device_id, device_user, description) \
                         VALUES ((SELECT device_id FROM user_device_view \
                                  WHERE username='$CURRENT_USER' and device_name='$CURRENT_DEVICE'), \
                              '$device_user', '$description')";
      if [ $? = 0 ]; then
        lognote "Add device user '$device_user' success!"
      fi

    elif [ "$op" = "3" ]; then      # Update device user information
      read -t 30 -p "Device user name: " device_user || continue 
      read -t 30 -p "Description: " description || continue

      valiate_name "device user name" "$device_user" ||  continue
      [ -z "$description" ] && logwarn "Description must not be blank!" && continue

      # Confirm Update?
      read -t 30 -p "Are your update device user: $device_user? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "UPDATE device_user SET description='$description', last_modified=CURRENT_TIMESTAMP \
                  WHERE device_user='$device_user' and \
                    device_id=(SELECT device_id FROM user_device_view \
                              WHERE username='$CURRENT_USER' and device_name='$CURRENT_DEVICE')"
      if [ $? = 0 ]; then
        lognote "Update device user '$device_user' success!"
      fi

    elif [ "$op" == "4" ]; then     # Delete device user
      read -t 30 -p "Device user name: " device_user || continue
      valiate_name "device user name" "$device_user" ||  continue

      # Confirm Delete?
      read -t 30 -p "Are your delete device user: $device_user? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "delete from device_user WHERE device_user='$device_user' and \
                  device_id=(SELECT device_id FROM user_device_view \
                             WHERE username='$CURRENT_USER' and device_name='$CURRENT_DEVICE')"
      if [ $? = 0 ]; then
        lognote "Delete device user '$device_user' success!"
      fi

    elif [ "$op" == "5" ]; then     # Refresh device user password
      # Confirm refresh?
      read -t 30 -p "Are your refresh device user password? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      local sqlpass="INSERT(TO_BASE64(LEFT(SHA2(UUID(), 256), 12)), \
                     FLOOR(1 + RAND() * 12), 1, \
                     SUBSTR('[!@#$%^&*()]', FLOOR(1 + RAND() * 12), 1))"
      mysql_exec "UPDATE device_user SET passtext=$sqlpass, last_modified=CURRENT_TIMESTAMP \
                  WHERE device_id=(SELECT device_id FROM user_device_view \
                                   WHERE username='$CURRENT_USER' and device_name='$CURRENT_DEVICE');"
      if [ $? = 0 ]; then
        lognote "Manual refresh password for device '$device_name' success!"
      fi

    else
      # Exit menu
      menu_exit || return $?
    fi
  done
}

enter_clinet_device_management() {
  while true; do
    # Choose an operation from menu
    getop_from_menu "$(cat <<EOF
=== MGBOX Client Managerment :: $(green Devices Managerment) System ===
User: $CURRENT_USER
Operation Menu:
  1. List device
  2. Add new device
  3. Update device description
  4. Delete device
  5. List device connect state
  x. Exit sub menu
EOF
)" || return $?

    # Handle operation:
    if [ "$op" == "1" ]; then       # List device
      ids="device_name, install_token, created_at, last_modified, description"
      data=$(OP=-te mysql "SELECT $ids FROM user_device_view WHERE username='$CURRENT_USER'");
      if [[ "$data" =~ failed|rror ]]; then
        logerr "List device failed: $data"
      else
        echo "$data"
      fi

    elif [ "$op" = "2" ]; then      # Add new device
      read -t 30 -p "Device Name: " device_name || continue 
      read -t 30 -p "Description: " description || continue 
      echo

      valiate_name "device name" "$device_name" ||  continue
      [ -z "$description" ] && logwarn "Description must not be blank!" && continue

      # Confirm Add?
      read -t 30 -p "Are your add new device: $device_name? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "INSERT INTO device (userid, device_name, description) \
                         VALUES ((SELECT userid FROM user WHERE username='$CURRENT_USER' LIMIT 1), \
                              '$device_name', '$description')";
      if [ $? = 0 ]; then
        lognote "Add device '$device_name' success!"
      fi

    elif [ "$op" = "3" ]; then      # Update device description
      read -t 30 -p "Device Name: " device_name || continue 
      read -t 30 -p "Description: " description || continue

      valiate_name "device name" "$device_name" ||  continue
      [ -z "$description" ] && logwarn "Description must not be blank!" && continue

      # Confirm Update?
      read -t 30 -p "Are your update device: $device_name? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "UPDATE device SET description='$description', last_modified=CURRENT_TIMESTAMP \
                  WHERE device_name='$device_name'"
      if [ $? = 0 ]; then
        lognote "Update device '$device_name' success!"
      fi

    elif [ "$op" == "4" ]; then     # Delete device
      read -t 30 -p "Device name: " device_name || continue
      valiate_name "device name" "$device_name" ||  continue

      # Confirm Delete?
      read -t 30 -p "Are your delete device: $device_name? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "delete from device where device_name='$device_name' and \
                  userid=(SELECT userid FROM user WHERE username='$CURRENT_USER' LIMIT 1)"
      if [ $? = 0 ]; then
        lognote "Delete device '$device_name' success!"
      fi

    elif [ "$op" == "5" ]; then     # List device connect state
      read -t 30 -p "Device name: " device_name || continue
      if [ -n "$device_name" ]; then
        valiate_name "device name" "$device_name" ||  continue
      fi

      # Set to list all if not set
      [ -z "$device_name" ] && device_name='%'
      data=$(OP=-te mysql "SELECT device_name, \
                                  IF ((CURRENT_TIMESTAMP - last_access) < 20, 'UP', 'Down') AS state, \
                                  client_ip, last_access, description \
                           FROM user_device_connect_state_view \
                           WHERE username='$CURRENT_USER' and device_name LIKE '$device_name'");
      if [[ "$data" =~ failed|rror ]]; then
        logerr "List device '$device_name' connect state failed: $data"
      else
        echo "$data"
      fi

    else
      # Exit menu
      menu_exit || return $?
    fi
  done
}

enter_clinet_system() {
  while true; do
    # Choose an operation from menu
    getop_from_menu "$(cat <<EOF
=== MGBOX $(green Client Managerment) System ===
Operation Menu:
  1. $(blue Device management)
  2. $(blue Device user management)
  3. Modify user password
  4. List device and users
  x. Exit sub menu
  X. Exit system
EOF
)" || return $?

    # Handle operation:
    if [ "$op" == "1" ]; then       # Device management
      enter_clinet_device_management

    elif [ "$op" = "2" ]; then      # Device user management
      read -t 30 -p "Device Name: " device_name || continue 
      valiate_name "device name" "$device_name" ||  continue

      data=$(mysql "SELECT device_name FROM user_device_view \
                           WHERE username='$CURRENT_USER' and device_name='$device_name'");
      if [[ "$data" != "$device_name"  ]]; then
        [ -z "$data" ] && data="can't found device!".
        logerr "Enter device '$device_name' failed: $data" && continue
      fi

      CURRENT_DEVICE="$device_name" 
      enter_clinet_device_user_management

    elif [ "$op" == "3" ]; then     # Modify user password
      read -t 30 -p "Old password: " -s old_passwd || continue
      echo
      read -t 30 -p "New password: " -s new_passwd || continue 
      echo
      read -t 30 -p "Confirm password: " -s confirm_passwd || continue 
      echo

      [ -z "$old_passwd" ] && logwarn "Old password must not be blank!" && continue
      [ -z "$new_passwd" ] && logwarn "New password must not be blank!" && continue
      [ "$confirm_passwd" != "$new_passwd" ] && logwarn "Confirm password mismatch!" && continue

      # Confirm Modify user password?
      read -t 30 -p "Are your sure modify password: $CURRENT_USER? [Yes|$(white No)] " yesno || continue
      [[ ! "$yesno" =~ (Y|y) ]] && echo "Your selection is 'no'." && continue

      mysql_exec "UPDATE user set password_hash=SHA2('$new_passwd', 256), last_modified=CURRENT_TIMESTAMP \
                  WHERE username='$CURRENT_USER' and password_hash=SHA2('$old_passwd', 256)";
      if [ $? = 0 ]; then
        lognote "Modify user '$username' password success!"
      fi

    elif [ "$op" = "4" ]; then      # List device and users
      read -t 30 -p "Device Name: " device_name || continue 

      # Set to list all if not set
      [ -z "$device_name" ] && device_name='%'

      ids="device_name, passtext, created_at, last_modified, description"
      data=$(OP=-te mysql "SELECT $ids FROM user_device_device_user_view \
                          WHERE username='$CURRENT_USER' and device_name LIKE '$device_name'");
      if [[ "$data" =~ failed|rror ]]; then
        logerr "List device '$device_name' failed: $data"
      else
        echo "$data"
      fi
    fi

    # Exit menu
    menu_exit || return $?
  done
}

app_main() {
  while true; do
    # Login to
    mgbox_login || return 1

    if [ "$CURRENT_USER" = "admin" ]; then
      enter_admin_system
    else
      enter_clinet_system
    fi

    # Manual exit or EOF(1)
    [ $? = 255 -o $? = 1 ] && break
  done
}

app_main
exit $?
