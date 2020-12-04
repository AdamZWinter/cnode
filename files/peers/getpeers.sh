#!/bin/bash

date=$(date '+%Y-%m-%d-%H-%M')

curl -s -o "/home/ec2-user/cnode/files/peers/new/$date.json" "https://api.clio.one/htopology/v1/fetch/?max=19"
