#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

green() { echo -e "\033[1;32m$@\033[0m"; }
blue() { echo -e "\033[1;34m$@\033[0m"; }
red() { echo -e "\033[1;31m$@\033[0m"; }
yellow() { echo -e "\033[1;33m$@\033[0m"; }
white() { echo -e "\033[1;37m$@\033[0m"; }


MGBOX_LOG_FILE=/var/log/mgbox.log
_log()    { local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ"); \
            echo "$TIMESTAMP [${FUNCNAME[2]}]: $@" | tee -a "$MGBOX_LOG_FILE"; }
loginfo() { _log "Info $@" 1>&2; }
lognote() { _log "$(green Notice): $@" 1>&2; }
logwarn() { _log "$(yellow Warning): $@" 1>&2; }
logerr()  { _log "$(red Error): $@" 1>&2; }
fatal()   { _log "$(red Error): $@" 1>&2; exit 1; }


mysql() {
  if [ -f /usr/bin/mysql ]; then
    /usr/bin/mysql ${OP:--NBe} "$@"
  else
    # docker exec -it mariadb mariadb -NBe "$@"
    docker exec -t mgbox-database-1 mariadb -u mgbox -pmgbox mgbox ${OP:--NBe} "$@"
  fi
}

mysql_exec() {
  local result=$(mysql "$@" 2>&1)
  [ -n "$result" ] && logerr "$result" && return 1
  return 0
}

# ptable() {
#   if [ -f /usr/bin/ptable ]; then
#     /usr/bin/ptable "$@"
#   else
#     while read -t 1 line; do
#       echo "$line"
#     done
#   fi
# }

valiate_name() {
  [ ${#2} -lt 3 ] && logerr "${1^} length is too short!" && return 1
  [[ ! "$2" =~ ^[a-zA-z0-9\-]+$ ]] && logerr "${1^} is not in charset '[a-zA-z0-9\-]'" && return 1
  return 0
}
