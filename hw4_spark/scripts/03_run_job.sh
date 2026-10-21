#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

HW="$(cd "$(dirname "$0")/.." && pwd)"
JOB_DIR="/tmp/spark-job"

log "Входные данные в HDFS: $SALES_RAW_DIR"
run_on "$SPARK_HOST" <<EOF || die "нет данных в $SALES_RAW_DIR — сначала hw3_hive/scripts/05_load_data.sh"
sudo -u $HADOOP_USER -i hdfs dfs -test -e $SALES_RAW_DIR && sudo -u $HADOOP_USER -i hdfs dfs -ls $SALES_RAW_DIR | tail -n +2 | awk '{print "  " \$5 " байт  " \$8}'
EOF

log "PySpark-задача -> $SPARK_HOST"
run_on "$SPARK_HOST" <<<"rm -rf $JOB_DIR && mkdir -p $JOB_DIR && chmod 755 $JOB_DIR"
copy_to "$SPARK_HOST" "$HW/jobs/sales_daily.py" "$JOB_DIR/sales_daily.py"

log "spark-submit --master yarn: $SALES_RAW_DIR -> $SPARK_DB.$SPARK_TABLE"
run_on "$SPARK_HOST" <<EOF
set -o pipefail
chmod 644 $JOB_DIR/sales_daily.py
LOG=$SPARK_LOG_DIR/sales_daily_\$(date +%Y%m%d_%H%M%S).log
sudo -u $HADOOP_USER -i $SPARK_HOME/bin/spark-submit --name hw4_sales_daily \
  $JOB_DIR/sales_daily.py --input $SALES_RAW_DIR --table $SPARK_DB.$SPARK_TABLE 2>&1 \
  | sudo -u $HADOOP_USER tee \$LOG \
  | grep -E 'applicationId=|defaultFS=|raw_rows=|table=|Submitted application|final status|^\||^\+|Error|Exception' \
  | grep -vE 'WARN' | sed 's/^/  /'
rc=\${PIPESTATUS[0]}
echo "  полный лог: \$LOG"
rm -rf $JOB_DIR
exit \$rc
EOF
log "Задача завершена. Проверка: $(dirname "$0")/04_verify_spark.sh"
