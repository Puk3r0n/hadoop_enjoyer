#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

log "Каталоги в HDFS для YARN/MapReduce"
run_on "$EDGE_HOST" <<EOF
set -e
H="sudo -u $HADOOP_USER -i hdfs dfs"
\$H -mkdir -p /tmp /app-logs /mr-history/tmp /mr-history/done /user
\$H -chmod 1777 /tmp /app-logs /mr-history/tmp
\$H -chmod 1770 /mr-history/done
echo "  /tmp /app-logs /mr-history готовы"
EOF

log "Старт ResourceManager"
start_daemon "$RESOURCEMANAGER_HOST" yarn resourcemanager

log "Старт NodeManager"
for host in "${NODEMANAGER_HOSTS[@]}"; do start_daemon "$host" yarn nodemanager; done

log "Старт JobHistory Server"
start_daemon "$JOBHISTORY_HOST" mapred historyserver

log "YARN запущен. Публикация интерфейсов: $(dirname "$0")/03_publish_ui.sh"
