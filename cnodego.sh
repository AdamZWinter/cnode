#!/bin/bash

  cardano-node run \
        --topology /root/cnode/files/topology.json \
        --config /root/cnode/files/config.json \
        --database-path /root/cnode/db \
        --socket-path /root/cnode/sockets/node0.socket \
        --host-addr 0.0.0.0 \
        --port 3001
