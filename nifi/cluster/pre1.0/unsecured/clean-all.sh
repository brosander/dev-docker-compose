#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

rm -rf "$BASE_DIR/dev-dockerfiles"
rm -rf "$BASE_DIR/ssh-key"
"$BASE_DIR/clean.sh"
