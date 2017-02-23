#!/bin/bash

set -e

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

cd "$BASE_DIR"

if [ -n "$(docker ps | awk '{print $NF}' | grep '^squid$')" ]; then
  echo "squid container already running"
elif [ -n "$(docker ps -a | awk '{print $NF}' | grep '^squid$')" ]; then
  echo "Starting squid container"
  docker start squid
else
  echo "squid container not found, creating"
  docker run -d --net ambari --name squid --hostname squid.ambari --restart always squid
fi

docker-compose up -d
