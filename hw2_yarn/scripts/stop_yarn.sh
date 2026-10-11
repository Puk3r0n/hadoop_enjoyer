#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"
stop_daemon "$JOBHISTORY_HOST" mapred historyserver
for host in "${NODEMANAGER_HOSTS[@]}"; do stop_daemon "$host" yarn nodemanager; done
stop_daemon "$RESOURCEMANAGER_HOST" yarn resourcemanager
