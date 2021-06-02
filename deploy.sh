#!/bin/sh

cd /home/dev/hugo.yusank.space && git pull
hugo -D
sudo supervisorctl restart hugo-web
