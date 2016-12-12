#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$BASE_DIR" ]; then
  echo "Couldn't resolve basedir, exiting before scary rm -rf"
  exit 1
fi

if [ -e "$BASE_DIR/target" ]; then
  "$BASE_DIR/target/socks.sh" stop
  "$BASE_DIR/target/teardown.sh"
fi

rm -rf "$BASE_DIR/target"
