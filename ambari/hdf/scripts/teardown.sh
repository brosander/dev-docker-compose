#!/bin/bash

set -e

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

cd "$BASE_DIR"

"$BASE_DIR/socks.sh" stop || echo "Socks wasn't running."

docker-compose down

if [ "killsquid" = "$1" ]; then
  if [ -n "$(docker ps | awk '{print $NF}' | grep '^squid$')" ]; then
    echo "Killing and removing squid container"
    docker kill squid
    docker rm squid
  elif [ -n "$(docker ps -a | awk '{print $NF}' | grep '^squid$')" ]; then
    echo "Removing squid container"
    docker rm squid
  else
    echo "Squid container not found running so not killed or removed"
  fi
else
  echo "If you want to kill and remove your squid container as well, use killsquid as the value for arg 1"
fi
