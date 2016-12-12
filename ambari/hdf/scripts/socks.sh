#!/bin/bash

set -e

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

cd "$BASE_DIR"

if [ -z "$DOCKER_HOST" ]; then
  IP="localhost"
else
  IP="$(docker-machine ip)"
fi

# http://stackoverflow.com/questions/2241063/bash-script-to-setup-a-temporary-ssh-tunnel/15198031#answer-15198031
if [ "$1" = "start" ]; then
  if [ -e "socks-proxy-ctrl" ]; then
    echo "Control file already present, stopping before starting"
    ssh -S socks-proxy-ctrl -O exit "root@$IP"
  fi
  PORT="$(docker-compose ps gateway | tail -n 1 | awk '{print $NF}' | sed 's/.*:\([^-]*\).*/\1/g')"
  ssh -M -S socks-proxy-ctrl -fnNT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "$BASE_DIR/../ssh-key/id_rsa" -p "$PORT" -D 1025 "root@$IP" 2>/dev/null
  echo "SOCKS proxy started"
elif [ "$1" = "stop" ]; then
  ssh -S socks-proxy-ctrl -O exit "root@$IP"
elif [ "$1" = "status" ]; then
  ssh -S socks-proxy-ctrl -O check "root@$IP"
else
  echo "Expected argument of start, stop, status"
fi
