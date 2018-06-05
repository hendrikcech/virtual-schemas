#!/usr/bin/env bash

# This script executes integration tests as defined in
# ./integration-test-data/integration-test-travis.yaml (currently only Exasol
# integration tests).

# An Exasol instance is run using the exasol/docker-db image. Therefore, a
# working installation of Docker and sudo privileges are required.

set -eu

cd "$(dirname "$0")/.."

config="$(pwd)/integration-test-data/integration-test-travis.yaml"

function cleanup() {
    docker rm -f exasoldb || true
    sudo rm -rf integration-test-data/exa || true
}
trap cleanup EXIT

mkdir -p integration-test-data/exa/etc
cp integration-test-data/EXAConf integration-test-data/exa/etc/EXAConf

docker pull exasol/docker-db:latest
docker run --name exasoldb \
    -p 8888:8888 \
    -p 6583:6583 \
    --detach \
    --privileged \
    --volume "$(pwd)/exa:/exa" \
    exasol/docker-db:latest

mvn clean package

# Wait for exaudfclient to be extracted and available
while [ $(docker exec exasoldb find /exa/data/bucketfs/bfsdefault/.dest -name exaudfclient -printf '.' | wc -c) -lt 1 ]; do
    sleep 1
done

# Upload virtualschema-jdbc-adapter jar and wait a bit to make sure it's available
mvn pre-integration-test -DskipTests -Pit -Dintegrationtest.configfile="$config"
sleep 60

mvn verify -Pit -Dintegrationtest.configfile="$config"
