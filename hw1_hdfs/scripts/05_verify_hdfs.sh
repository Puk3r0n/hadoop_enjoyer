#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

expected=${#DATANODE_HOSTS[@]}
fail=0

log "Ожидание регистрации DataNode (до 60 с)"
for _ in $(seq 1 30); do
  live=$(run_on "$EDGE_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfsadmin -report 2>/dev/null | grep -oP 'Live datanodes \(\K[0-9]+' || echo 0")
  [[ $live -ge $expected ]] && break
  sleep 2
done

log "Ожидание выхода NameNode из safe mode"
run_on "$EDGE_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfsadmin -safemode wait" | sed 's/^/  /'

log "hdfs dfsadmin -report"
report=$(run_on "$EDGE_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfsadmin -report")
echo "$report" | grep -E 'Configured Capacity|Live datanodes|Dead datanodes|^Name:|Decommission Status' | sed 's/^/  /'
live=$(echo "$report" | grep -oP 'Live datanodes \(\K[0-9]+' || echo 0)
dead=$(echo "$report" | grep -oP 'Dead datanodes \(\K[0-9]+' || echo 0)
[[ $live -eq $expected ]] && echo "  OK: живых DataNode $live из $expected" || { echo "  FAIL: живых DataNode $live из $expected"; fail=1; }
[[ $dead -eq 0 ]] && echo "  OK: мёртвых DataNode нет" || { echo "  FAIL: мёртвых DataNode $dead"; fail=1; }

log "Веб-интерфейс NameNode (из внутренней сети)"
code=$(run_on "$EDGE_HOST" <<<"curl -s -o /dev/null -w '%{http_code}' http://$NAMENODE_HOST:9870/dfshealth.html")
[[ $code == 200 ]] && echo "  OK: http://$NAMENODE_HOST:9870 -> $code" || { echo "  FAIL: NameNode UI -> $code"; fail=1; }
code=$(run_on "$EDGE_HOST" <<<"curl -s -o /dev/null -w '%{http_code}' http://$SECONDARY_NAMENODE_HOST:9868/status.html")
[[ $code == 200 ]] && echo "  OK: http://$SECONDARY_NAMENODE_HOST:9868 (Secondary NN) -> $code" || { echo "  FAIL: Secondary NN UI -> $code"; fail=1; }

log "Состояние NameNode через JMX"
run_on "$EDGE_HOST" <<EOF | sed 's/^/  /'
curl -s 'http://$NAMENODE_HOST:9870/jmx?qry=Hadoop:service=NameNode,name=FSNamesystemState' \
  | python3 -c 'import json,sys; b=json.load(sys.stdin)["beans"][0]; print("FSState:", b["FSState"], "| NumLiveDataNodes:", b["NumLiveDataNodes"], "| NumDeadDataNodes:", b["NumDeadDataNodes"], "| UnderReplicatedBlocks:", b["UnderReplicatedBlocks"])'
EOF

log "Тест записи/чтения (фактор репликации $DFS_REPLICATION)"
run_on "$EDGE_HOST" <<EOF | sed 's/^/  /'
set -e
H="sudo -u $HADOOP_USER -i hdfs"
echo "hello hdfs \$(date)" > /tmp/hdfs_smoke.txt && chmod 644 /tmp/hdfs_smoke.txt
\$H dfs -mkdir -p /tmp/smoke
\$H dfs -put -f /tmp/hdfs_smoke.txt /tmp/smoke/
\$H dfs -cat /tmp/smoke/hdfs_smoke.txt
\$H fsck /tmp/smoke/hdfs_smoke.txt -files -blocks -locations 2>/dev/null | grep -E 'Average block replication|Status'
\$H dfs -rm -r -skipTrash /tmp/smoke >/dev/null
EOF

log "Ошибки в логах (ERROR/FATAL, без штатных сообщений об остановке)"
for host in $(all_hosts); do
  n=$(run_on "$host" <<<"sudo grep -hE ' (ERROR|FATAL) ' $HADOOP_LOG_DIR/hadoop-$HADOOP_USER-*.log 2>/dev/null | grep -vE '$SHUTDOWN_NOISE' | wc -l")
  echo "  [$host] ERROR/FATAL строк: $n"
done

[[ $fail -eq 0 ]] && log "HDFS здоров" || die "Проверка не пройдена"
