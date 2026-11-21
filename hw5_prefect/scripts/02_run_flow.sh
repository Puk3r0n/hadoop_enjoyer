#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

HW="$(cd "$(dirname "$0")/.." && pwd)"
FLOW_DIR="/tmp/prefect-flow"

log "Входные данные в HDFS: $SALES_RAW_DIR"
run_on "$SPARK_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfs -test -e $SALES_RAW_DIR" \
  || die "нет данных в $SALES_RAW_DIR — сначала hw3_hive/scripts/05_load_data.sh"

log "Поток Prefect -> $SPARK_HOST"
run_on "$SPARK_HOST" <<<"rm -rf $FLOW_DIR && mkdir -p $FLOW_DIR && chmod 755 $FLOW_DIR"
copy_to "$SPARK_HOST" "$HW/flows/sales_pipeline.py" "$FLOW_DIR/sales_pipeline.py"

log "prefect flow hw5-sales-monthly: $SALES_RAW_DIR -> $FLOW_DB.$FLOW_TABLE"
run_on "$SPARK_HOST" <<EOF2
set -o pipefail
chmod 644 $FLOW_DIR/sales_pipeline.py
LOG=$PREFECT_LOG_DIR/sales_monthly_\$(date +%Y%m%d_%H%M%S).log
sudo -u $HADOOP_USER -i env PREFECT_HOME=$PREFECT_HOME_DIR SPARK_HOME=$SPARK_HOME PYSPARK_PYTHON=python3 \
  PREFECT_LOGGING_LEVEL=INFO $PREFECT_VENV/bin/python $FLOW_DIR/sales_pipeline.py \
  --input $SALES_RAW_DIR --table $FLOW_DB.$FLOW_TABLE 2>&1 \
  | sudo -u $HADOOP_USER tee \$LOG \
  | grep -E "Task run|Flow run|applicationId=|fs.defaultFS=|байт|прочитано|валидных|table=|Error|Exception|Traceback" \
  | grep -v ' WARN ' | sed 's/^/  /'
rc=\${PIPESTATUS[0]}
echo "  полный лог: \$LOG"
rm -rf $FLOW_DIR
exit \$rc
EOF2
log "Поток завершён. Проверка: $(dirname "$0")/03_verify.sh"
