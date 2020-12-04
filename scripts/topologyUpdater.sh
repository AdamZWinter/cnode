#!/bin/bash


######################################
# User Variables - Change as desired #
######################################

CNODE_PORT=3001
CNODE_VALENCY=1                                           # (Optional) for multi-IP hostnames
MAX_PEERS=19                                              # Maximum number of peers to return on successful fetch

######################################
# Do NOT modify code below           #
######################################


  fail_cnt=0
  while ! blockNo=$(curl -s -m 10 -H 'Accept: application/json' "http://127.0.0.1:12788" 2>/dev/null | jq -er '.cardano.node.ChainDB.metrics.blockNum.int.val //0' ); do
    ((fail_cnt++))
    [[ ${fail_cnt} -eq 5 ]] && echo "5 consecutive EKG queries failed, aborting!"
    echo "(${fail_cnt}/5) Failed to grab blockNum from node EKG metrics, sleeping for 30s before retrying... (ctrl-c to exit)"
    sleep 30
  done

curl -s "https://api.clio.one/htopology/v1/?port=${CNODE_PORT}&blockNo=${blockNo}&valency=${CNODE_VALENCY}" | tee -a /home/ec2-user/cnode/files/peers/topologyUpdater_lastresult.json

exit 0
