#!/bin/bash

set -e

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

NUM_NODES="3"
AMBARI_URL="http://public-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.4.0.1/ambari.repo"
MPACK_URL="http://public-repo-1.hortonworks.com/HDF/centos6/2.x/updates/2.0.0.0/tars/hdf_ambari_mp/hdf-ambari-mpack-2.0.0.0-579.tar.gz"
SUFFIX="_compose"

function printUsageAndExit() {
  echo "usage: $0 -m mpack_dir -p pub_key_file [-n num_target_nodes] [-a] [-h]"
  echo "       -h or --help                    print this message and exit"
  echo "       -a or --ambariUrl               URL of ambari repo (default: $AMBARI_URL)"
  echo "       -m or --mpackUrl                URL of Mpack to download, only used if no mpack dir present (default: $MPACK_URL)"
  echo "       -n or --numNodes                number of hdf nodes (default: $NUM_NODES)"
  echo "       -s or --suffix                  Image suffix for built images (default: $SUFFIX)"
  exit 1
}

function buildImage() {
  local TAG="$1$SUFFIX"
  local CMD="docker build -t $TAG ."
  local DIR="$2"

  echo "Building Dockerfile in $DIR:"

  if [ -n "$3" ]; then
    local CMD="$( echo "$3" | sed "s/TAG_ARG/$TAG/g")"
  fi

  OUTPUT="$( cd "$DIR" && eval "$CMD" )"
  if [ $? -ne 0 ]; then
    echo "$OUTPUT"
    echo "$CMD FAILED in Directory: $DIR"
    exit 1
  else
    echo "$CMD SUCCEEDED: $( echo "$OUTPUT" | tail -n 1 )"
  fi
  echo
}

# see https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash/14203146#14203146
while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
    -a|--ambariUrl)
    AMBARI_URL="$2"
    shift
    ;;
    -n|--numNodes)
    NUM_NODES="$2"
    shift
    ;;
    -m|--mpackUrl)
    MPACK_URL="$2"
    shift
    ;;
    -h|--help)
    printUsageAndExit
    ;;
    *)
    echo "Unknown option: $key"
    echo
    printUsageAndExit
    ;;
  esac
  shift
done

echo
echo "Apache Ambari URL: $AMBARI_URL"
echo "Number of nodes: $NUM_NODES"
echo "Mpack URL: $MPACK_URL"
echo "Suffix: $SUFFIX"
echo

# Dockerfile repo
if [ ! -e "$BASE_DIR/dev-dockerfiles" ]; then
  git clone https://github.com/brosander/dev-dockerfiles.git
  "$BASE_DIR/dev-dockerfiles/nifi/ubuntu/buildStack.sh"
fi

buildImage ambari "$BASE_DIR/dev-dockerfiles/ambari/server/centos6" "docker build --build-arg repo=\"$AMBARI_URL\" -t TAG_ARG ."
buildImage squid "$BASE_DIR/dev-dockerfiles/squid/centos6"
buildImage ubuntu-ssh "$BASE_DIR/dev-dockerfiles/openssh-server/ubuntu"
buildImage centos6-ssh "$BASE_DIR/dev-dockerfiles/openssh-server/centos6"
buildImage gateway "$BASE_DIR/dev-dockerfiles/ambari/gateway/ubuntu"
buildImage root-ambari-agent "$BASE_DIR/dev-dockerfiles/ambari/agent/root/centos6"
buildImage non-root-ambari-agent "$BASE_DIR/dev-dockerfiles/ambari/agent/non-root/centos6" "docker build --build-arg repo=\"$AMBARI_URL\" -t TAG_ARG ."

if [ ! -e "$BASE_DIR/ssh-key" ]; then
  mkdir "$BASE_DIR/ssh-key"
  ssh-keygen -t rsa -b 4096 -f "$BASE_DIR/ssh-key/id_rsa"
fi

if [ ! -e "$BASE_DIR/mpack" ]; then
  wget -P mpack "$MPACK_URL"
fi

#Transient target directory
if [ -e "$BASE_DIR/target" ]; then
  echo "Cleaning previous output"
  "$BASE_DIR/clean.sh"
fi

echo
echo "Generating docker-compose.yml"

mkdir "$BASE_DIR/target"

echo "#SUFFIX: $SUFFIX" > "$BASE_DIR/target/docker-compose.yml"
echo "version: '2'" >> "$BASE_DIR/target/docker-compose.yml"
echo "services:" >> "$BASE_DIR/target/docker-compose.yml"
echo "  gateway:" >> "$BASE_DIR/target/docker-compose.yml"
echo "    container_name: gateway" >> "$BASE_DIR/target/docker-compose.yml"
echo "    hostname: gateway.ambari" >> "$BASE_DIR/target/docker-compose.yml"
echo "    image: gateway" >> "$BASE_DIR/target/docker-compose.yml"
echo "    restart: always" >> "$BASE_DIR/target/docker-compose.yml"
echo "    ports:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - 22" >> "$BASE_DIR/target/docker-compose.yml"
echo "    networks:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - ambari" >> "$BASE_DIR/target/docker-compose.yml"
echo "    entrypoint:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - /root/start.sh" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - $(cat "$BASE_DIR/ssh-key/id_rsa.pub")" >> "$BASE_DIR/target/docker-compose.yml"
echo "    volumes:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - /dev/urandom:/dev/random" >> "$BASE_DIR/target/docker-compose.yml"
echo  >> "$BASE_DIR/target/docker-compose.yml"

echo "  squid:" >> "$BASE_DIR/target/docker-compose.yml"
echo "    container_name: squid" >> "$BASE_DIR/target/docker-compose.yml"
echo "    hostname: squid.ambari" >> "$BASE_DIR/target/docker-compose.yml"
echo "    image: squid" >> "$BASE_DIR/target/docker-compose.yml"
echo "    restart: always" >> "$BASE_DIR/target/docker-compose.yml"
echo "    networks:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - ambari" >> "$BASE_DIR/target/docker-compose.yml"

docker tag ambari "ambari$SUFFIX"

echo "  ambari:" >> "$BASE_DIR/target/docker-compose.yml"
echo "    container_name: ambari" >> "$BASE_DIR/target/docker-compose.yml"
echo "    hostname: ambari.ambari" >> "$BASE_DIR/target/docker-compose.yml"
echo "    image: ambari$SUFFIX" >> "$BASE_DIR/target/docker-compose.yml"
echo "    restart: always" >> "$BASE_DIR/target/docker-compose.yml"
echo "    networks:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - ambari" >> "$BASE_DIR/target/docker-compose.yml"
echo "    volumes:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - \"$BASE_DIR/mpack:/build\"" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - /dev/urandom:/dev/random" >> "$BASE_DIR/target/docker-compose.yml"
echo "    environment:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - YUM_PROXY=http://squid:3128" >> "$BASE_DIR/target/docker-compose.yml"

for i in $(seq 1 $NUM_NODES); do
  docker tag non-root-ambari-agent "centos6$i$SUFFIX"

  echo  >> "$BASE_DIR/target/docker-compose.yml"
  echo "  centos6$i:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    container_name: centos6$i" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    hostname: centos6$i.ambari" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    image: centos6$i$SUFFIX" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    restart: always" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    networks:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - ambari" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    volumes:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - /dev/urandom:/dev/random" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    environment:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - YUM_PROXY=http://squid:3128" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    entrypoint:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - /root/start-agent.sh" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - $(cat "$BASE_DIR/ssh-key/id_rsa.pub")" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - ambari" >> "$BASE_DIR/target/docker-compose.yml"
done

echo  >> "$BASE_DIR/target/docker-compose.yml"
echo "networks:" >> "$BASE_DIR/target/docker-compose.yml"
echo "  ambari:" >> "$BASE_DIR/target/docker-compose.yml"
echo "    external: true" >> "$BASE_DIR/target/docker-compose.yml"

if [ -z "$(docker network ls | awk '{print $2}' | grep '^ambari$')" ]; then
  echo "Creating ambari network"
  docker network create --gateway 172.18.1.1 --subnet 172.18.1.0/24 nifi
else
  echo "ambari network already exists, not creating"
fi

cp "$BASE_DIR/scripts/"*.sh "$BASE_DIR/target/"
