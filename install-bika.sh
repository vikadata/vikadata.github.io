#!/usr/bin/env bash

##
# install bika selfhost(docker) online
##
set -e

notes () {
    cat << EOF
======== WARM TIPS ========
Before you submit any github issue, please do the following check:
* make sure the docker daemon is running
* make sure you use docker compose v2: recommend 2.x.x, got $(docker compose version --short 2>/dev/null || echo not install)
* check your internet connection if timeout happens
* check for potential port conflicts if you have local services listening on all interfaces (e.g. another redis container listening on *:6379)
===========================
EOF
}

trap notes ERR

if ! docker info >/dev/null 2>&1; then
   os=$(uname -s)
   arch=$(uname -m)
   if [ "$os" == "Linux" ]; then
     wget -C https://download-selfhosted.bika.ai/docker-compose/${arch}/docker-28.0.1.tgz
     tar -zxvf docker.tgz -C /tmp
     mkdir -p /etc/docker
     mkdir -p /usr/local/lib/docker/cli-plugins

     mv /tmp/docker/bin/* /usr/local/bin/
     cp -rf /tmp/docker/docker.service /usr/lib/systemd/system/
     if [ ! -e "/usr/bin/docker" ];then
        ln -s /usr/local/bin/docker /usr/bin/
     fi
     if [ ! -e "/usr/local/lib/docker/cli-plugins/docker-compose" ]; then
        ln -s /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/
     fi
     systemctl daemon-reload
     systemctl enable docker
     systemctl start docker
   else
     echo "Docker daemon or Docker Desktop is not running... please check" 2>&1
     false
     exit 1
   fi
fi

DOWNLOAD_URL='https://download-selfhosted.bika.ai/latest/bika-docker-amd64.tar.gz'

: "${DOWNLOAD_URL?✗ missing env}"

curl -fLo bika-docker-amd64.tar.gz "${DOWNLOAD_URL}"
tar -zxvf bika-docker-amd64.tar.gz  && cd bika
[ ! -f .env ] && cat .env.template > .env

docker compose --profile all down -v --remove-orphans
for i in {1..50}; do
    if docker compose --profile all pull; then
        if docker compose --profile all up -d; then
            break
        fi
    fi
    sleep 6
done
