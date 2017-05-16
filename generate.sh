#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

source "$BASE_DIR/init-env.sh"

export PYTHONPATH="$BASE_DIR/generator:$PYTHONPATH"
SCRIPT="$BASE_DIR/generator/$1/main.py"
shift
python "$SCRIPT" "$@"
