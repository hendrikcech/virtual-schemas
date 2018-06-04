#!/usr/bin/env bash

# This script executes integration tests as defined in
# ./integration-test-data/integration-test-travis.yaml (currently only Exasol
# integration tests).

# An Exasol instance is run using the exasol/docker-db image. Therefore, a
# working installation of Docker and sudo privileges are required.

location="$(dirname "$0")"
config="$location/integration-test-data/integration-test-travis.yaml"

cd $location

docker pull exasol/docker-db:latest
docker run --name exasoldb \
    -p 8888:8888 \
    -p 6583:6583 \
    --detach \
    --privileged \
    --stop-timeout 120 \
    exasol/docker-db:latest

# Wait for EXAConf to be generated
while [ -z "$W_PW" ]; do
    W_PW=$(docker exec exasoldb cat /exa/etc/EXAConf | awk '/WritePasswd/{ print $3; }' | base64 -d)
    sleep 1
done
sed -i -e "s/BUCKET_FS_PASSWORD/$W_PW/" "$config"

mvn clean package

# Wait for exaudfclient to be extracted and available
while [ $(docker exec exasoldb find /exa/data/bucketfs/bfsdefault/.dest -name exaudfclient -printf '.' | wc -c) -lt 1 ]; do
    sleep 1
done

# Upload virtualschema-jdbc-adapter jar and wait a bit to make sure it's available
mvn pre-integration-test -DskipTests -Pit -Dintegrationtest.configfile="$config"
sleep 60

mvn verify -Pit -Dintegrationtest.configfile="$config"
