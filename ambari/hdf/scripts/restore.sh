#!/bin/bash

set -e

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

SNAPSHOT_PREFIX="$1"
SNAPSHOT_SUFFIX="$(grep "#SUFFIX:" "$BASE_DIR/docker-compose.yml" | sed 's/#SUFFIX: //g')"

if [ -z "$SNAPSHOT_PREFIX" ]; then
  echo "Must provide snapshot prefix as only argument."
  exit 1
fi

SNAPSHOT_OUTPUT="$(docker images | grep "^${SNAPSHOT_PREFIX}_\\S*${SNAPSHOT_SUFFIX} " | awk '{print $1}')"
SERVICES="$(echo "$SNAPSHOT_OUTPUT" | sed "s/${SNAPSHOT_PREFIX}_//g" | sed "s/$SNAPSHOT_SUFFIX\$//g")"

for image in $SNAPSHOT_OUTPUT; do
  docker tag "$image" "$(echo "$image" | sed "s/${SNAPSHOT_PREFIX}_//g")"
done

echo "$SERVICES" | xargs docker-compose kill
echo "$SERVICES" | xargs docker-compose rm -f
echo "$SERVICES" | xargs docker-compose up -d --no-deps
