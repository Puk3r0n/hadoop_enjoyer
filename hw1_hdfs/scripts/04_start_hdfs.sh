#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

log "Форматирование NameNode на $NAMENODE_HOST (если ещё не отформатирован)"
run_on "$NAMENODE_HOST" <<EOF
set -e
if sudo test -f $HADOOP_DATA_DIR/namenode/current/VERSION; then
  echo "  NameNode уже отформатирован — пропускаю (данные сохраняются)"
else
  sudo -u $HADOOP_USER -i $HADOOP_HOME/bin/hdfs namenode -format -nonInteractive -clusterId hadoop-hw-cluster
fi
EOF

log "Старт NameNode"
start_daemon "$NAMENODE_HOST" hdfs namenode

log "Старт Secondary NameNode"
start_daemon "$SECONDARY_NAMENODE_HOST" hdfs secondarynamenode

log "Старт DataNode"
for host in "${DATANODE_HOSTS[@]}"; do start_daemon "$host" hdfs datanode; done

log "HDFS запущен. Проверка: $(dirname "$0")/05_verify_hdfs.sh"
