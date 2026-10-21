#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

JDBC="jdbc:hive2://$HIVE_HOST:$HIVESERVER2_PORT/default"
TABLE="$SPARK_DB.$SPARK_TABLE"
fail=0
ok()  { echo "  OK: $*"; }
bad() { echo "  FAIL: $*"; fail=1; }

q() {
  run_on "$HIVE_HOST" <<EOF
sudo -u $HADOOP_USER -i $HIVE_HOME/bin/beeline -u "$JDBC" -n $HADOOP_USER --silent=true --showHeader=false --outputformat=csv2 -e "$1" 2>/dev/null
EOF
}

log "Spark на $SPARK_HOST"
run_on "$SPARK_HOST" <<EOF | sed 's/^/  /'
sudo -u $HADOOP_USER -i $SPARK_HOME/bin/spark-submit --version 2>&1 | grep -m1 -oE 'version [0-9.]+' | sed 's/^/Spark /'
grep -E '^spark\.(master|submit.deployMode|executor\.(memory|instances)|yarn.archive)' $SPARK_HOME/conf/spark-defaults.conf
grep -A1 metastore.uris $SPARK_HOME/conf/hive-site.xml | grep -oE '<value>[^<]+' | sed 's/<value>/hive.metastore.uris = /'
EOF

log "Приложение в YARN"
app=$(run_on "$SPARK_HOST" <<<"sudo -u $HADOOP_USER -i yarn application -list -appStates FINISHED 2>/dev/null | awk '\$2 == \"hw4_sales_daily\" {print \$1}' | sort | tail -1")
[[ -n $app ]] || die "в YARN нет завершённых приложений hw4_sales_daily — сначала 03_run_job.sh"
status=$(run_on "$SPARK_HOST" <<<"sudo -u $HADOOP_USER -i yarn application -status $app 2>/dev/null")
echo "$status" | grep -E 'Application-Id|Application-Name|Application-Type|Queue|Final-State|Start-Time|Finish-Time|Tracking-URL' | sed 's/^\t*/  /'
echo "$status" | grep -q 'Final-State : SUCCEEDED' && ok "$app SUCCEEDED" || bad "$app завершился не SUCCEEDED"
hosts=$(run_on "$SPARK_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfs -cat $SPARK_EVENT_LOG_DIR/$app 2>/dev/null | grep SparkListenerExecutorAdded | grep -oE '\"Host\":\"[^\"]+\"' | cut -d'\"' -f4 | sort -u | tr '\n' ' '")
echo "  executor запускались на: $hosts"
[[ -n $hosts ]] && ok "executor работали в контейнерах YARN на узлах кластера" || bad "в event log нет executor"

log "Таблица $TABLE в Hive Metastore (PostgreSQL)"
run_on "$HIVE_HOST" <<EOF | sed 's/^/  /'
sudo -u postgres psql -qtA -d $METASTORE_DB_NAME -c "SELECT d.\"NAME\" || '.' || t.\"TBL_NAME\" || ' (' || t.\"TBL_TYPE\" || ', создана ' || to_timestamp(t.\"CREATE_TIME\") || ')' FROM \"TBLS\" t JOIN \"DBS\" d USING (\"DB_ID\") WHERE d.\"NAME\" = '$SPARK_DB'"
sudo -u postgres psql -qtA -d $METASTORE_DB_NAME -c "SELECT 'партиций в metastore: ' || count(*) FROM \"PARTITIONS\" p JOIN \"TBLS\" t USING (\"TBL_ID\") JOIN \"DBS\" d USING (\"DB_ID\") WHERE d.\"NAME\" = '$SPARK_DB' AND t.\"TBL_NAME\" = '$SPARK_TABLE'"
EOF

log "Чтение стандартным клиентом hive (beeline)"
serde=$(q "DESCRIBE FORMATTED $TABLE" | grep -E '^SerDe Library:' | awk -F, '{print $2}' | tr -d ' ')
echo "  SerDe: $serde"
[[ $serde == *ParquetHiveSerDe ]] && ok "таблица записана в Hive-совместимом формате" || bad "SerDe $serde, Hive может не прочитать таблицу"

parts=$(q "SHOW PARTITIONS $TABLE")
echo "$parts" | tr '\n' ' ' | sed 's/^/  /'; echo
n=$(echo "$parts" | grep -c '^tx_month=' || true)
[[ $n -eq 12 ]] && ok "SHOW PARTITIONS: $n" || bad "партиций $n, ожидалось 12"

run_on "$EDGE_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfs -count $HIVE_WAREHOUSE_DIR/$SPARK_DB.db/$SPARK_TABLE/tx_month=* | awk '{print \"  \" \$4 \"  файлов: \" \$2 \"  байт: \" \$3}' | sed 's|.*/tx_month|  tx_month|'"

counts=$(q "SELECT count(*), sum(tx_count) FROM $TABLE")
src=$(q "SELECT count(*) FROM hw3.sales")
echo "  $TABLE: строк ${counts%%,*}, транзакций в них ${counts##*,}; в исходной hw3.sales: $src"
[[ ${counts##*,} == "$src" && $src -eq $SALES_ROWS ]] && ok "все $src транзакций попали в агрегаты" || bad "sum(tx_count)=${counts##*,}, hw3.sales=$src"

log "Выборка из одной партиции: лидеры по выручке 2025-03-01"
q "SELECT tx_date, region, category, tx_count, revenue, avg_check, card_share FROM $TABLE WHERE tx_month = '2025-03' AND tx_date = '2025-03-01' AND category_rank = 1 ORDER BY revenue DESC" | sed 's/^/  /'

log "Сверка Hive и Spark: выручка за месяц по сырым данным и по витрине"
a=$(q "SELECT sum(amount) FROM hw3.sales WHERE tx_month = '2025-06'")
b=$(q "SELECT sum(revenue) FROM $TABLE WHERE tx_month = '2025-06'")
echo "  hw3.sales 2025-06: $a, $TABLE 2025-06: $b"
[[ -n $a && $a == "$b" ]] && ok "суммы совпадают" || bad "суммы различаются"

[[ $fail -eq 0 ]] && log "Spark на YARN записал партиционированную таблицу, Hive её читает" || die "Проверка не пройдена"
