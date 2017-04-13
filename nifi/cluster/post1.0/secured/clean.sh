#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_NAME="secured"

if [ -n "$1" ]; then
  PROJECT_NAME="$1"
fi

if [ -z "$BASE_DIR" ]; then
  echo "Couldn't resolve basedir, exiting before scary rm -rf"
  exit 1
fi

rm -rf "$BASE_DIR/$PROJECT_NAME"
