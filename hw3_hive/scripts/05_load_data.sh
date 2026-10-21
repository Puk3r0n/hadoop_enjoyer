#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

HW="$(cd "$(dirname "$0")/.." && pwd)"
JDBC="jdbc:hive2://$HIVE_HOST:$HIVESERVER2_PORT/default"

log "Файлы задания -> $HIVE_HOST"
run_on "$HIVE_HOST" <<<"rm -rf /tmp/hive-load && mkdir -p /tmp/hive-load && chmod 755 /tmp/hive-load"
for f in "$HW"/data/generate_sales.py "$HW"/sql/*.sql; do copy_to "$HIVE_HOST" "$f" "/tmp/hive-load/$(basename "$f")"; done

log "Генерация CSV ($SALES_ROWS строк) и выгрузка в HDFS $SALES_RAW_DIR"
run_on "$HIVE_HOST" <<EOF
set -e
cd /tmp/hive-load
chmod 644 *
python3 generate_sales.py $SALES_ROWS sales.csv
chmod 644 sales.csv
echo "  sales.csv: \$(wc -l < sales.csv) строк с заголовком, \$(du -h sales.csv | cut -f1)"
H="sudo -u $HADOOP_USER -i hdfs dfs"
\$H -mkdir -p $SALES_RAW_DIR
\$H -put -f /tmp/hive-load/sales.csv $SALES_RAW_DIR/sales.csv
\$H -ls $SALES_RAW_DIR | sed 's/^/  /'
EOF

beeline() {
  run_on "$HIVE_HOST" <<EOF
sudo -u $HADOOP_USER -i $HIVE_HOME/bin/beeline -u "$JDBC" -n $HADOOP_USER --silent=${2:-true} --showWarnings=false \
  --hivevar raw_dir=$SALES_RAW_DIR -f /tmp/hive-load/$1 2>&1 | grep -vE '^(SLF4J|WARNING|$)'
exit \${PIPESTATUS[0]}
EOF
}

log "DDL: база hw3, внешняя таблица sales_raw, партиционированная sales"
beeline 01_ddl.sql | sed 's/^/  /'

log "Загрузка в партиции (INSERT OVERWRITE ... PARTITION (tx_month), задача MapReduce на YARN)"
beeline 02_load_partitions.sql false | { grep -E 'Starting Job|Partition \{|rows affected|Error|FAILED' || true; } | sed -E 's/^INFO  : //; s/^/  /'

log "Результат"
beeline 03_check.sql | sed 's/^/  /'

run_on "$HIVE_HOST" <<<"rm -rf /tmp/hive-load"
log "Данные загружены. Проверка: $(dirname "$0")/06_verify_hive.sh"
