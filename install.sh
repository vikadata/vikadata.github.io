#!/bin/bash

mkdir -p /data/vika-k3s/tmp /data/vika-k3s/run && cd /data/vika-k3s/tmp
curl -s 'https://download.vika.cn/vika/k3s/latest/install/vika-private-cloud.tar.gz' -o vika-private-cloud.tar.gz
tar -zxvf /data/vika-k3s/tmp/vika-private-cloud.tar.gz -C /data/vika-k3s/run && rm -rf /data/vika-k3s/tmp/vika-private-cloud.tar.gz
chmod +x /data/vika-k3s/run/vika && /data/vika-k3s/run/vika install
