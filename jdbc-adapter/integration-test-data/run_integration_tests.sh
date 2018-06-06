#!/usr/bin/env bash

# This script executes integration tests as defined in
# ./integration-test-data/integration-test-travis.yaml (currently only Exasol
# integration tests).

# An Exasol instance is run using the exasol/docker-db image. Therefore, a
# working installation of Docker and sudo privileges are required.

set -eux

cd "$(dirname "$0")/.."

config="$(pwd)/integration-test-data/integration-test-travis.yaml"

function cleanup() {
    docker rm -f exasoldb || true
    sudo rm -rf integration-test-data/exa || true
}
# trap cleanup EXIT

docker pull exasol/docker-db:latest
docker run --name exasoldb \
    -p 8899:8888 \
    -p 6594:6583 \
    --detach \
    --privileged \
    exasol/docker-db:latest

docker logs -f exasoldb &

(docker logs -f --tail 0 exasoldb &) 2>&1 | grep -q -i 'stage4: All stages finished'
sleep 30

docker exec exasoldb dwad_client stop-wait DB1

docker exec exasoldb sed -i -e '/Checksum/c\    Checksum = COMMIT' /exa/etc/EXAConf
docker exec exasoldb sed -i -e '/WritePasswd/c\        WritePasswd = d3JpdGU=' /exa/etc/EXAConf
docker exec exasoldb sed -i -e '/Params/c\    Params = -etlJdbcJavaEnv -Djava.security.egd=/dev/./urandom' /exa/etc/EXAConf

docker exec exasoldb sh -c 'rm /exa/etc/EXAConf.*'

docker stop exasoldb
docker start exasoldb
(docker logs -f --tail 0 exasoldb &) 2>&1 | grep -q -i 'stage4: All stages finished'
sleep 30

docker exec exasoldb cat /exa/etc/EXAConf

mvn clean package

# Wait for exaudfclient to be extracted and available
while [ $(docker exec exasoldb find /exa/data/bucketfs/bfsdefault/.dest -name exaudfclient -printf '.' | wc -c) -lt 1 ]; do
    sleep 1
done

# Upload virtualschema-jdbc-adapter jar and wait a bit to make sure it's available
mvn pre-integration-test -DskipTests -Pit -Dintegrationtest.configfile="$config"

sleep 60

mvn verify -Pit -Dintegrationtest.configfile="$config"
