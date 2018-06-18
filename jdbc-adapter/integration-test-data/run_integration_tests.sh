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
trap cleanup EXIT

mkdir -p integration-test-data/exa/{etc,data/storage}
cp integration-test-data/EXAConf integration-test-data/exa/etc/EXAConf
dd if=/dev/zero of=integration-test-data/exa/data/storage/dev.1.data bs=1 count=1 seek=4G
touch integration-test-data/exa/data/storage/dev.1.meta

docker pull exasol/docker-db:6.0.10-d1
docker run \
    --name exasoldb \
    -p 8899:8888 \
    -p 6594:6583 \
    --detach \
    --privileged \
    -v "$(pwd)/integration-test-data/exa:/exa" \
    exasol/docker-db:latest \
    init-sc --node-id 11

docker logs -f exasoldb &

(docker logs -f --tail 0 exasoldb &) 2>&1 | grep -q -i 'stage4: All stages finished'
sleep 30

docker exec exasoldb sh -c 'ls /exa/etc; cat /exa/etc/EXAConf'

mvn clean package

# Wait for exaudfclient to be extracted and available
while [ $(docker exec exasoldb find /exa/data/bucketfs/bfsdefault/.dest -name exaudfclient -printf '.' | wc -c) -lt 1 ]; do
    sleep 1
done

# Upload virtualschema-jdbc-adapter jar and wait a bit to make sure it's available
mvn pre-integration-test -DskipTests -Pit -Dintegrationtest.configfile="$config"

sleep 60

mvn verify -Pit -Dintegrationtest.configfile="$config"
