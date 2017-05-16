#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

if [ -e "$BASE_DIR/venv" ]; then
  source "$BASE_DIR/venv/bin/activate"
else
  virtualenv --no-site-packages --prompt='(compose-venv) ' "$BASE_DIR/venv"
  source "$BASE_DIR/venv/bin/activate"
  pip install Jinja2
fi
