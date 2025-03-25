#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source $SCRIPT_DIR/utils.sh

startup_mgbox() {
    # Set default settings
    DOCKER_COMPOSE_FILE=${DOCKER_COMPOSE_FILE:-docker-compose.yml}
    DOCKER_COMPSE=$(which docker-compose 2>&1 > /dev/null)
    DOCKER_COMPSE=${DOCKER_COMPSE:-"docker compose"}
    docker_compose() {
        lognote "$DOCKER_COMPSE -f $DOCKER_COMPOSE_FILE '$@'"
        $DOCKER_COMPSE -f $DOCKER_COMPOSE_FILE "$@"
    }

    # Start mgbox
    lognote "Starting mgbox ..."
    docker_compose down && docker_compose up -d || fatal "Starting mgbox failed!"
}

deploy_all_in_one() {
    # Deploy mgbox Server
    startup_mgbox

    # Install Mgbox Agent to each VM
    ./install_to_vms.sh

    lognote "Install All successfull!"
}

main() {
    [[ "$1" =~ -h ]] && \
        echo "Useage: $(basename $0) [-h|--help] <docker-compose[-prod].yml>" && exit 1

    [ -n "$1" ] && DOCKER_COMPOSE_FILE=$1
    deploy_all_in_one
}

main "$@"
