#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"
for s in hiveserver2:HiveServer2 metastore:HiveMetaStore; do
  svc=${s%%:*} cls=${s#*:}
  run_on "$HIVE_HOST" <<EOF
if pgrep -u $HADOOP_USER -f "$cls" >/dev/null; then
  sudo pkill -u $HADOOP_USER -f "$cls"
  for _ in \$(seq 1 30); do pgrep -u $HADOOP_USER -f "$cls" >/dev/null || break; sleep 1; done
  sudo rm -f $HADOOP_DATA_DIR/hive/$svc.pid
  echo "  [\$(hostname)] $svc остановлен"
else
  echo "  [\$(hostname)] $svc не был запущен"
fi
EOF
done
