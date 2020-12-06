#!/bin/bash

cardano-db-sync-extended \
	--config /home/ec2-user/cnode/files/config.json \
	--socket-path /home/ec2-user/cnode/sockets/node0.socket \
	--state-dir /home/ec2-user/cardano-db-sync/ledger-state/ \
	--schema-dir /home/ec2-user/cardano-db-sync/schema/
