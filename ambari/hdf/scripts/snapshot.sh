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

if [ -n "$(docker images | grep "^$SNAPSHOT_PREFIX")" ]; then
  echo "Already have images that start with $SNAPSHOT_PREFIX"
  exit 1
fi

ALL_CLUSTER_NODES="$(docker-compose ps)"
RELEVANT_CLUSTER_NODES="$(echo "$(echo "$ALL_CLUSTER_NODES" | grep "^ambari " && echo "$ALL_CLUSTER_NODES" | grep "^centos6")" | awk '{print $1}')"

echo "Relevant containers: " $RELEVANT_CLUSTER_NODES

echo "Pausing nodes."
echo "$RELEVANT_CLUSTER_NODES" | xargs docker-compose pause

for node in $RELEVANT_CLUSTER_NODES; do
  echo "Committing node $node"
  docker commit $node "$SNAPSHOT_PREFIX"_"$node$SNAPSHOT_SUFFIX"
done

echo "Unpausing nodes."
echo "$RELEVANT_CLUSTER_NODES" | xargs docker-compose unpause
