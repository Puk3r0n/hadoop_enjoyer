#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

SERVICES=(
  "metastore:HiveMetaStore:$HIVE_METASTORE_PORT:90"
  "hiveserver2:HiveServer2:$HIVESERVER2_PORT:180"
)

for s in "${SERVICES[@]}"; do
  IFS=: read -r svc cls port wait_s <<<"$s"
  log "Старт $svc"
  run_on "$HIVE_HOST" <<EOF
set -e
if pgrep -u $HADOOP_USER -f "$cls" >/dev/null; then
  echo "  [\$(hostname)] $svc уже запущен"
  exit 0
fi
sudo -u $HADOOP_USER -i bash -c 'nohup $HIVE_HOME/bin/hive --service $svc > $HIVE_LOG_DIR/$svc.out 2>&1 & echo \$! > $HADOOP_DATA_DIR/hive/$svc.pid'
for _ in \$(seq 1 $wait_s); do
  ss -ltn | grep -q ":$port " && { echo "  [\$(hostname)] $svc запущен, порт $port"; exit 0; }
  sudo kill -0 \$(cat $HADOOP_DATA_DIR/hive/$svc.pid) 2>/dev/null || break
  sleep 1
done
echo "  [\$(hostname)] $svc не поднялся, хвост $HIVE_LOG_DIR/$svc.out:"
tail -20 $HIVE_LOG_DIR/$svc.out
exit 1
EOF
done
log "Hive запущен. Загрузка данных: $(dirname "$0")/05_load_data.sh"
