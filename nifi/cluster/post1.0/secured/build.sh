#!/bin/bash

NUM_NODES="1"
DEBUG_PORT=""
PROJECT_NAME="secured"

function printUsageAndExit() {
  echo "usage: $0 -m mpack_dir -p pub_key_file [-n num_target_nodes] [-a] [-h]"
  echo "       -h or --help                    print this message and exit"
  echo "       -a or --nifiArchive             path to Apache NiFi archive"
  echo "       -t or --nifiToolkit             path to Apache NiFi toolkit"
  echo "       -n or --numNodes                number of NiFi nodes (default: $NUM_NODES)"
  echo "       -p or --project                 project name to use (default: $PROJECT_NAME)"
  echo "       -d or --debug                   debug port to use (default: NONE)"
  exit 1
}

# see https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash/14203146#14203146
while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
    -a|--nifiArchive)
    NIFI_ARCHIVE="$2"
    shift
    ;;
    -t|--nifiToolkit)
    NIFI_TOOLKIT="$2"
    shift
    ;;
    -n|--numNodes)
    NUM_NODES="$2"
    shift
    ;;
    -p|--project)
    PROJECT_NAME="$2"
    shift
    ;;
    -d|--debug)
    DEBUG_PORT="$2"
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

if [ -z "$NIFI_ARCHIVE" ]; then
  echo "Must specify Apache NiFi archive (-a)"
  echo
  printUsageAndExit
fi

if [ -z "$NIFI_TOOLKIT" ]; then
  echo "Must specify Apache NiFi toolkit (-t)"
  echo
  printUsageAndExit
fi

echo
echo "Apache NiFi archive: $NIFI_ARCHIVE"
echo "Apache NiFi toolkit: $NIFI_TOOLKIT"
echo "Number of nodes: $NUM_NODES"
echo "Project name: $PROJECT_NAME"
echo "Debug port: $DEBUG_PORT"
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
if [ -e "$BASE_DIR/$PROJECT_NAME" ]; then
  echo "Cleaning previous output"
  "$BASE_DIR/clean.sh" "$PROJECT_NAME"
fi

mkdir -p "$BASE_DIR/$PROJECT_NAME/base"
cp -r "$BASE_DIR/ssh-key" "$BASE_DIR/$PROJECT_NAME"
cp -r "$BASE_DIR/support" "$BASE_DIR/$PROJECT_NAME"
cp -r "$BASE_DIR/scripts"/* "$BASE_DIR/$PROJECT_NAME"

unzip "$NIFI_TOOLKIT" -d "$BASE_DIR/$PROJECT_NAME"

echo "Extracting config files that need to be updated"
NIFI_CONF_DIR="$(dirname "$(unzip -l "$NIFI_ARCHIVE" | grep "nifi.properties$" | head -n1 | awk '{print $NF}')")"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/nifi.properties" > "$BASE_DIR/$PROJECT_NAME/base/nifi.properties"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/bootstrap.conf" > "$BASE_DIR/$PROJECT_NAME/base/bootstrap.conf"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/state-management.xml" > "$BASE_DIR/$PROJECT_NAME/base/state-management.xml"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/zookeeper.properties" > "$BASE_DIR/$PROJECT_NAME/base/zookeeper.properties"
unzip -p "$NIFI_ARCHIVE" "$NIFI_CONF_DIR/authorizers.xml" > "$BASE_DIR/$PROJECT_NAME/base/authorizers.xml"

function setProperty() {
  sed -i.bak 's/^'"$1"'=.*$/'"$1"'='"$2"'/g' "$3"
}

echo "Creating base node directory"
mkdir -p "$BASE_DIR/$PROJECT_NAME/basenode"
cp "$BASE_DIR/$PROJECT_NAME/base/nifi.properties" "$BASE_DIR/$PROJECT_NAME/basenode/nifi.properties"

cp "$BASE_DIR/$PROJECT_NAME/base/bootstrap.conf" "$BASE_DIR/$PROJECT_NAME/basenode/bootstrap.conf"
if [ -n "$DEBUG_PORT" ]; then
  sed -i.bak 's/#java.arg.debug=.*/java.arg.debug=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address='"$DEBUG_PORT"'/g' "$BASE_DIR/$PROJECT_NAME/basenode/bootstrap.conf"
fi

setProperty nifi.cluster.is.node true "$BASE_DIR/$PROJECT_NAME/basenode/nifi.properties"
setProperty nifi.cluster.node.protocol.port 9001 "$BASE_DIR/$PROJECT_NAME/basenode/nifi.properties"
setProperty nifi.state.management.embedded.zookeeper.start true "$BASE_DIR/$PROJECT_NAME/basenode/nifi.properties"
setProperty nifi.cluster.flow.election.max.candidates "$NUM_NODES" "$BASE_DIR/$PROJECT_NAME/basenode/nifi.properties"

cp "$BASE_DIR/$PROJECT_NAME/base/zookeeper.properties" "$BASE_DIR/$PROJECT_NAME/basenode/zookeeper.properties"
sed -i.bak 's/^server.1=$//g' "$BASE_DIR/$PROJECT_NAME/basenode/zookeeper.properties"
setProperty dataDir '.\/conf\/state\/zookeeper' "$BASE_DIR/$PROJECT_NAME/basenode/zookeeper.properties"

cp "$BASE_DIR/$PROJECT_NAME/base/state-management.xml" "$BASE_DIR/$PROJECT_NAME/basenode/state-management.xml"

CONNECT_STRING=""
for i in $(seq 1 $NUM_NODES); do
  echo "server.$i=node$i:2888:3888" >> "$BASE_DIR/$PROJECT_NAME/basenode/zookeeper.properties"
  CONNECT_STRING="$CONNECT_STRING,node$i:2181"
done
CONNECT_STRING="$(echo "$CONNECT_STRING" | sed 's/^,//g')"
sed -i.bak 's/<property name="Connect String">.*/<property name="Connect String">'"$CONNECT_STRING"'<\/property>/g' "$BASE_DIR/$PROJECT_NAME/basenode/state-management.xml"
setProperty nifi.zookeeper.connect.string "$CONNECT_STRING" "$BASE_DIR/$PROJECT_NAME/basenode/nifi.properties"

cp "$BASE_DIR/$PROJECT_NAME/base/authorizers.xml" "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"
sed -i.bak 's/<property name="Initial Admin Identity"><\/property>/<property name="Initial Admin Identity">CN=admin, OU=NIFI<\/property>/g' "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"
sed -i.bak 's/<\/authorizer>/<!--<\/authorizer>/g' "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"
sed -i.bak 's/<\/authorizers>/<\/authorizers>-->/g' "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"

echo "" >> "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"

for i in $(seq 1 $NUM_NODES); do
  echo "        <property name=\"Node Identity $i\">CN=node$i, OU=NIFI</property>" >> "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"
done

echo "    </authorizer>" >> "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"
echo "</authorizers>" >> "$BASE_DIR/$PROJECT_NAME/basenode/authorizers.xml"

TLS_TOOLKIT_SH="$(find "$PROJECT_NAME"/nifi-toolkit-* -name tls-toolkit.sh)"

"$TLS_TOOLKIT_SH" standalone -C "CN=admin, OU=NIFI" -o "$BASE_DIR/$PROJECT_NAME"

for i in $(seq 1 $NUM_NODES); do
  echo "Configuring node$i"
  "$TLS_TOOLKIT_SH" standalone -f "$BASE_DIR/$PROJECT_NAME/basenode/nifi.properties" -n node$i -o "$BASE_DIR/$PROJECT_NAME"
  cp -rn "$BASE_DIR/$PROJECT_NAME/basenode/"* "$BASE_DIR/$PROJECT_NAME/node$i/"
  setProperty nifi.web.http.host node$i "$BASE_DIR/$PROJECT_NAME/node$i/nifi.properties"
  setProperty nifi.cluster.node.address node$i "$BASE_DIR/$PROJECT_NAME/node$i/nifi.properties"
  setProperty nifi.remote.input.socket.host node$i "$BASE_DIR/$PROJECT_NAME/node$i/nifi.properties"
  mkdir -p "$BASE_DIR/$PROJECT_NAME/node$i/state/zookeeper"
  echo "$i" > "$BASE_DIR/$PROJECT_NAME/node$i/state/zookeeper/myid"
done

echo
echo "Generating docker-compose.yml"

echo "version: '3'" > "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "services:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"

echo "  squid-gateway:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    container_name: ${PROJECT_NAME}-squid-gateway" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    hostname: squid-gateway.$PROJECT_NAME" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    image: squid-alpine" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    restart: always" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    ports:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "      - 3128" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    volumes:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "      - \"$BASE_DIR/$PROJECT_NAME/support/squid-gateway/:/opt/squid-conf/\"" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    entrypoint:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "      - /root/start.sh" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo  >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"

echo "  gateway:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    container_name: ${PROJECT_NAME}-sshgateway" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    image: ubuntu-openssh-server" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    restart: always" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    ports:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "      - 22" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "    entrypoint:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "      - /root/start.sh" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
echo "      - $(cat "$BASE_DIR/ssh-key/id_rsa.pub")" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"

for i in $(seq 1 $NUM_NODES); do
  echo  >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "  node$i:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "    container_name: ${PROJECT_NAME}-node$i" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "    hostname: node$i" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "    image: nifi" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "    restart: always" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "    ports:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "      - 2181" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "      - 2888" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "      - 3888" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  if [ -n "$DEBUG_PORT" ]; then
    echo "      - $DEBUG_PORT" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  fi
  echo "      - 9001" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "    volumes:" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "      - ./node$i:/opt/nifi-conf" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "      - $NIFI_ARCHIVE:/opt/nifi-archive/nifi-archive.zip" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
  echo "      - /dev/urandom:/dev/random" >> "$BASE_DIR/$PROJECT_NAME/docker-compose.yml"
done
