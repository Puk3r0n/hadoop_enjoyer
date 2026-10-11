#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"
for host in "${DATANODE_HOSTS[@]}"; do stop_daemon "$host" hdfs datanode; done
stop_daemon "$SECONDARY_NAMENODE_HOST" hdfs secondarynamenode
stop_daemon "$NAMENODE_HOST" hdfs namenode
