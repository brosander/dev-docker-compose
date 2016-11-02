#!/bin/bash

if [ -z "$1" ]; then
  echo "Must specify NiFi archive zip file to use"
  exit 1
fi

if [ -z "$2" ]; then
  NUM_NODES="1"
else
  NUM_NODES="$2"
fi

NIFI_ARCHIVE="$1"

echo
echo "Apache NiFi archive: $NIFI_ARCHIVE"
echo "Number of nodes: $NUM_NODES"
echo

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in#answer-246128
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd | sed 's/\/$//g' )"

# Dockerfile repo
if [ ! -e "$BASE_DIR/dev-dockerfiles" ]; then
  git clone https://github.com/brosander/dev-dockerfiles.git
  "$BASE_DIR/dev-dockerfiles/nifi/ubuntu/buildStack.sh"
fi

if [ ! -e "$BASE_DIR/ssh-key" ]; then
  mkdir "$BASE_DIR/ssh-key"
  ssh-keygen -t rsa -b 4096 -f "$BASE_DIR/ssh-key/id_rsa"
fi

#Transient target directory
if [ -e "$BASE_DIR/target" ]; then
  echo "Cleaning previous output"
  "$BASE_DIR/clean.sh"
fi

mkdir -p "$BASE_DIR/target/base"

echo "Extracting config files that need to be updated"
NIFI_CONF_DIR="$(dirname "$(unzip -l "$NIFI_ARCHIVE" | grep "nifi.properties$" | head -n1 | awk '{print $NF}')")"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/nifi.properties" > "$BASE_DIR/target/base/nifi.properties"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/state-management.xml" > "$BASE_DIR/target/base/state-management.xml"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/zookeeper.properties" > "$BASE_DIR/target/base/zookeeper.properties"

function setProperty() {
  sed -i '' 's/^'"$1"'=.*$/'"$1"'='"$2"'/g' "$3"
}

echo "Creating NCM directory"
mkdir "$BASE_DIR/target/ncm"
cp "$BASE_DIR/target/base/nifi.properties" "$BASE_DIR/target/ncm/nifi.properties"
setProperty nifi.cluster.is.manager true "$BASE_DIR/target/ncm/nifi.properties"
setProperty nifi.cluster.manager.address ncm.nifi "$BASE_DIR/target/ncm/nifi.properties"
setProperty nifi.cluster.manager.protocol.port 9001 "$BASE_DIR/target/ncm/nifi.properties"

echo "Creating base node directory"
mkdir -p "$BASE_DIR/target/basenode"
cp "$BASE_DIR/target/base/nifi.properties" "$BASE_DIR/target/basenode/nifi.properties"
setProperty nifi.cluster.is.node true "$BASE_DIR/target/basenode/nifi.properties"
setProperty nifi.cluster.node.protocol.port 9001 "$BASE_DIR/target/basenode/nifi.properties"
setProperty nifi.cluster.node.unicast.manager.address ncm.nifi "$BASE_DIR/target/basenode/nifi.properties"
setProperty nifi.cluster.node.unicast.manager.protocol.port 9001 "$BASE_DIR/target/basenode/nifi.properties"
setProperty nifi.state.management.embedded.zookeeper.start true "$BASE_DIR/target/basenode/nifi.properties"

cp "$BASE_DIR/target/base/zookeeper.properties" "$BASE_DIR/target/basenode/zookeeper.properties"
sed -i '' 's/^server.1=$//g' "$BASE_DIR/target/basenode/zookeeper.properties"
setProperty dataDir '.\/conf\/state\/zookeeper' "$BASE_DIR/target/basenode/zookeeper.properties"

cp "$BASE_DIR/target/base/state-management.xml" "$BASE_DIR/target/basenode/state-management.xml"

CONNECT_STRING=""
for i in $(seq 1 $NUM_NODES); do
  echo "server.$i=node$i.nifi:2888:3888" >> "$BASE_DIR/target/basenode/zookeeper.properties"
  CONNECT_STRING="$CONNECT_STRING,node$i.nifi:2181"
done
CONNECT_STRING="$(echo "$CONNECT_STRING" | sed 's/^,//g')"
sed -i '' 's/<property name="Connect String">.*/<property name="Connect String">'"$CONNECT_STRING"'<\/property>/g' "$BASE_DIR/target/basenode/state-management.xml"

for i in $(seq 1 $NUM_NODES); do
  echo "Configuring node$i"
  cp -r "$BASE_DIR/target/basenode" "$BASE_DIR/target/node$i"
  setProperty nifi.web.http.host node$i.nifi "$BASE_DIR/target/node$i/nifi.properties"
  setProperty nifi.cluster.node.address node$i.nifi "$BASE_DIR/target/node$i/nifi.properties"
  setProperty nifi.remote.input.socket.host node$i.nifi "$BASE_DIR/target/node$i/nifi.properties"
  mkdir -p "$BASE_DIR/target/node$i/state/zookeeper"
  echo "$i" > "$BASE_DIR/target/node$i/state/zookeeper/myid"
done

echo
echo "Generating docker-compose.yml"

echo "version: '2'" > "$BASE_DIR/target/docker-compose.yml"
echo "services:" >> "$BASE_DIR/target/docker-compose.yml"
echo "  gateway:" >> "$BASE_DIR/target/docker-compose.yml"
echo "    container_name: gateway" >> "$BASE_DIR/target/docker-compose.yml"
echo "    image: ubuntu-openssh-server" >> "$BASE_DIR/target/docker-compose.yml"
echo "    restart: always" >> "$BASE_DIR/target/docker-compose.yml"
echo "    ports:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - 22" >> "$BASE_DIR/target/docker-compose.yml"
echo "    networks:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - nifi" >> "$BASE_DIR/target/docker-compose.yml"
echo "    entrypoint:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - /root/start.sh" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - $(cat "$BASE_DIR/ssh-key/id_rsa.pub")" >> "$BASE_DIR/target/docker-compose.yml"
echo  >> "$BASE_DIR/target/docker-compose.yml"
echo "  ncm:" >> "$BASE_DIR/target/docker-compose.yml"
echo "    container_name: ncm" >> "$BASE_DIR/target/docker-compose.yml"
echo "    image: nifi" >> "$BASE_DIR/target/docker-compose.yml"
echo "    restart: always" >> "$BASE_DIR/target/docker-compose.yml"
echo "    ports:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - 8080" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - 9001" >> "$BASE_DIR/target/docker-compose.yml"
echo "    networks:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - nifi" >> "$BASE_DIR/target/docker-compose.yml"
echo "    volumes:" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - ./ncm:/opt/nifi-conf" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - $NIFI_ARCHIVE:/opt/nifi-archive/nifi-archive.zip" >> "$BASE_DIR/target/docker-compose.yml"
echo "      - /dev/urandom:/dev/random" >> "$BASE_DIR/target/docker-compose.yml"

for i in $(seq 1 $NUM_NODES); do
  echo  >> "$BASE_DIR/target/docker-compose.yml"
  echo "  node$i:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    container_name: node$i" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    image: nifi" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    restart: always" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    ports:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - 2181" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - 2888" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - 3888" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - 9001" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    networks:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - nifi" >> "$BASE_DIR/target/docker-compose.yml"
  echo "    volumes:" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - ./node$i:/opt/nifi-conf" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - $NIFI_ARCHIVE:/opt/nifi-archive/nifi-archive.zip" >> "$BASE_DIR/target/docker-compose.yml"
  echo "      - /dev/urandom:/dev/random" >> "$BASE_DIR/target/docker-compose.yml"
done

echo  >> "$BASE_DIR/target/docker-compose.yml"
echo "networks:" >> "$BASE_DIR/target/docker-compose.yml"
echo "  nifi:" >> "$BASE_DIR/target/docker-compose.yml"
echo "    external: true" >> "$BASE_DIR/target/docker-compose.yml"

if [ -z "$(docker network ls | awk '{print $2}' | grep '^nifi$')" ]; then
  echo "Creating nifi network"
  docker network create --gateway 172.24.1.1 --subnet 172.24.1.0/24 nifi
else
  echo "nifi network already exists, not creating"
fi
