#!/usr/bin/env bash

# This script executes integration tests as defined in
# integration-test-travis.yaml (currently only Exasol integration tests).

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

# Setup directory "exa" with pre-configured EXAConf to attach it to the exasoldb docker container
mkdir -p integration-test-data/exa/{etc,data/storage}
cp integration-test-data/EXAConf integration-test-data/exa/etc/EXAConf
dd if=/dev/zero of=integration-test-data/exa/data/storage/dev.1.data bs=1 count=1 seek=4G
touch integration-test-data/exa/data/storage/dev.1.meta

# TODO use image `latest`
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

# Wait until database is ready
(docker logs -f --tail 0 exasoldb &) 2>&1 | grep -q -i 'stage4: All stages finished'
sleep 30

mvn -q clean package

# Upload virtualschema-jdbc-adapter jar and wait a bit to make sure it's available
# If tests fail with the following error message, try waiting longer:
# '/buckets/bfsdefault/default/virtualschema-jdbc-adapter-dist-1.0.1-SNAPSHOT.jar':
# No such file or directory (Session: 1605583229540089387)
mvn -q pre-integration-test -DskipTests -Pit -Dintegrationtest.configfile="$config"
# sleep 30

# linked=0
# while [ $linked -eq 0 ]; do
#     docker exec exasoldb grep -r -i 'File.*virtualschema-jdbc-adapter.*linked' /exa/logs/cored
#     linked=$(docker exec exasoldb grep -r -i 'File.*virtualschema-jdbc-adapter.*linked' /exa/logs/cored | wc -l)
#     sleep 5
# done

docker exec exasoldb ls /exa/logs/cored

# (docker exec exasoldb find /exa/logs/cored -iname '*bucket*' -print0 | \
#      xargs -0 -I {} \
#            docker exec exasoldb tail -f -n +0 {} &) | \
#     grep -q -i 'File.*virtualschema-jdbc-adapter.*linked'
(docker exec exasoldb sh -c 'tail -f -n +0 /exa/logs/cored/*bucket*' &) | \
    grep -q -i 'File.*virtualschema-jdbc-adapter.*linked'

docker exec exasoldb sh -c 'cat /exa/logs/cored/*bucket*'

mvn -q verify -Pit -Dintegrationtest.configfile="$config" -Dintegrationtest.skipTestSetup=true
