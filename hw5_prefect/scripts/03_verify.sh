#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

JDBC="jdbc:hive2://$HIVE_HOST:$HIVESERVER2_PORT/default"
TABLE="$FLOW_DB.$FLOW_TABLE"
fail=0
ok()  { echo "  OK: $*"; }
bad() { echo "  FAIL: $*"; fail=1; }

q() {
  run_on "$HIVE_HOST" <<EOF2
sudo -u $HADOOP_USER -i $HIVE_HOME/bin/beeline -u "$JDBC" -n $HADOOP_USER --silent=true --showHeader=false --outputformat=csv2 -e "$1" 2>/dev/null
EOF2
}

log "Последний запуск потока"
last=$(run_on "$SPARK_HOST" <<<"ls -t $PREFECT_LOG_DIR/sales_monthly_*.log 2>/dev/null | head -1")
[[ -n $last ]] || die "нет логов потока — сначала 02_run_flow.sh"
echo "  $last"
for s in "1. Spark-сессия под YARN" "2. Подключение к HDFS" "3. Чтение данных из HDFS" "4. Трансформации" "5. Сохранение таблицы"; do
  run_on "$SPARK_HOST" <<<"sudo grep -F \"$s\" $last | grep -q 'Finished in state Completed'" \
    && ok "задача «$s» Completed" || bad "задача «$s» не завершилась успешно"
done
run_on "$SPARK_HOST" <<<"sudo grep -E \"Flow run '[^']+' - Finished in state Completed\" $last | tail -1 | sed 's/^/  /'"
run_on "$SPARK_HOST" <<<"sudo grep -qE \"Flow run '[^']+' - Finished in state Completed\" $last" \
  && ok "поток hw5-sales-monthly Completed" || bad "поток не Completed"

log "Приложение Spark в YARN"
app=$(run_on "$SPARK_HOST" <<<"sudo -u $HADOOP_USER -i yarn application -list -appStates FINISHED 2>/dev/null | awk '\$2 == \"hw5_sales_monthly\" {print \$1}' | sort | tail -1")
[[ -n $app ]] || die "в YARN нет приложений hw5_sales_monthly"
status=$(run_on "$SPARK_HOST" <<<"sudo -u $HADOOP_USER -i yarn application -status $app 2>/dev/null")
echo "$status" | grep -E 'Application-Id|Application-Name|Application-Type|Final-State' | sed 's/^\t*/  /'
echo "$status" | grep -q 'Final-State : SUCCEEDED' && ok "$app SUCCEEDED" || bad "$app не SUCCEEDED"
hosts=$(run_on "$SPARK_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfs -cat $SPARK_EVENT_LOG_DIR/$app 2>/dev/null | grep SparkListenerExecutorAdded | grep -oE '\"Host\":\"[^\"]+\"' | cut -d'\"' -f4 | sort -u | tr '\n' ' '")
echo "  executor запускались на: $hosts"
[[ -n $hosts ]] && ok "executor работали в контейнерах YARN" || bad "в event log нет executor"

log "Таблица $TABLE (beeline)"
serde=$(q "DESCRIBE FORMATTED $TABLE" | grep -E '^SerDe Library:' | awk -F, '{print $2}' | tr -d ' ')
echo "  SerDe: $serde"
[[ $serde == *ParquetHiveSerDe ]] && ok "Hive-совместимый формат" || bad "SerDe $serde"
n=$(q "SHOW PARTITIONS $TABLE" | grep -c '^tx_month=' || true)
[[ $n -eq 12 ]] && ok "партиций: $n" || bad "партиций $n, ожидалось 12"

counts=$(q "SELECT count(*), sum(tx_count) FROM $TABLE")
src=$(q "SELECT count(*) FROM hw3.sales")
echo "  $TABLE: строк ${counts%%,*}, транзакций в них ${counts##*,}; в hw3.sales: $src"
[[ ${counts##*,} == "$src" ]] && ok "все транзакции попали в агрегаты" || bad "sum(tx_count)=${counts##*,}, hw3.sales=$src"

a=$(q "SELECT sum(amount) FROM hw3.sales WHERE tx_month = '2025-06'")
b=$(q "SELECT sum(revenue) FROM $TABLE WHERE tx_month = '2025-06'")
echo "  выручка 2025-06: hw3.sales $a, $TABLE $b"
[[ -n $a && $a == "$b" ]] && ok "выручка сходится с Hive" || bad "выручка различается"

log "Пример: лидер каждого региона в 2025-06 — доля в выручке региона и рост к маю"
q "SELECT tx_month, region, category, tx_count, revenue, region_share, mom_growth FROM (SELECT *, row_number() OVER (PARTITION BY region ORDER BY revenue DESC) rn FROM $TABLE WHERE tx_month = '2025-06') x WHERE rn = 1 ORDER BY revenue DESC" | sed 's/^/  /'

[[ $fail -eq 0 ]] && log "Поток Prefect запустил Spark на YARN и записал таблицу, Hive её читает" || die "Проверка не пройдена"
