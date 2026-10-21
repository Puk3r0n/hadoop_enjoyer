#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

JDBC="jdbc:hive2://$HIVE_HOST:$HIVESERVER2_PORT/default"
fail=0
ok()   { echo "  OK: $*"; }
bad()  { echo "  FAIL: $*"; fail=1; }

q() {
  run_on "$1" <<EOF
sudo -u $HADOOP_USER -i $HIVE_HOME/bin/beeline -u "$JDBC" -n $2 --silent=true --showHeader=false --outputformat=csv2 -e "$3" 2>/dev/null
EOF
}

log "Процессы и порты на $HIVE_HOST"
run_on "$HIVE_HOST" <<EOF | sed 's/^/  /'
for c in HiveMetaStore HiveServer2; do
  pid=\$(pgrep -u $HADOOP_USER -f \$c | head -1)
  [[ -n \$pid ]] && echo "\$c pid \$pid, RSS \$(( \$(ps -o rss= -p \$pid) / 1024 )) МБ" || echo "\$c НЕ ЗАПУЩЕН"
done
ss -ltn | awk 'NR>1{print \$4}' | grep -E ':($HIVE_METASTORE_PORT|$HIVESERVER2_PORT|$HIVESERVER2_UI_PORT|5432)\$' | sed 's/^/слушает /'
EOF
for p in "$HIVE_METASTORE_PORT" "$HIVESERVER2_PORT" "$HIVESERVER2_UI_PORT"; do
  run_on "$HIVE_HOST" <<<"ss -ltn | grep -q ':$p '" && ok "порт $p открыт" || bad "порт $p не слушается"
done

log "Metastore не embedded: схема в PostgreSQL, сервис metastore отдельным процессом"
run_on "$HIVE_HOST" <<EOF | sed 's/^/  /'
sudo grep -A1 -E 'ConnectionURL|metastore.uris' $HIVE_HOME/conf/hive-site.xml | grep -oE '<value>[^<]+' | sed 's/<value>//'
sudo -u postgres psql -qtA -d $METASTORE_DB_NAME -c 'SELECT "SCHEMA_VERSION" FROM "VERSION"' | sed 's/^/schema version в PostgreSQL: /'
sudo -u postgres psql -qtA -d $METASTORE_DB_NAME -c "SELECT d.\"NAME\" || '.' || t.\"TBL_NAME\" || ' (' || t.\"TBL_TYPE\" || ')' FROM \"TBLS\" t JOIN \"DBS\" d USING (\"DB_ID\") ORDER BY 1" | sed 's/^/таблица в metastore: /'
sudo -u postgres psql -qtA -d $METASTORE_DB_NAME -c 'SELECT count(*) FROM "PARTITIONS"' | sed 's/^/партиций в metastore: /'
EOF

log "Веб-интерфейс HiveServer2"
code=$(run_on "$EDGE_HOST" <<<"curl -s -o /dev/null -w '%{http_code}' -m 15 http://$HIVE_HOST:$HIVESERVER2_UI_PORT/")
[[ $code == 200 ]] && ok "http://$HIVE_HOST:$HIVESERVER2_UI_PORT/ -> $code" || bad "HiveServer2 UI -> $code"

log "Партиции hw3.sales"
parts=$(q "$HIVE_HOST" "$HADOOP_USER" "SHOW PARTITIONS hw3.sales")
echo "$parts" | sed 's/^/  /'
n=$(echo "$parts" | grep -c '^tx_month=' || true)
[[ $n -eq 12 ]] && ok "партиций: $n" || bad "партиций $n, ожидалось 12"

log "Каталоги партиций в HDFS"
loc=$(q "$HIVE_HOST" "$HADOOP_USER" "DESCRIBE FORMATTED hw3.sales" | grep -E '^Location:' | awk -F, '{print $2}' | tr -d ' ')
echo "  Location: $loc"
run_on "$EDGE_HOST" <<<"sudo -u $HADOOP_USER -i hdfs dfs -count ${loc#hdfs://*:$HDFS_PORT}/tx_month=* | awk '{print \"  \" \$4 \"  файлов: \" \$2 \"  байт: \" \$3}'"

log "Число строк: исходный CSV против партиционированной таблицы"
raw=$(q "$HIVE_HOST" "$HADOOP_USER" "SELECT count(*) FROM hw3.sales_raw WHERE tx_id IS NOT NULL")
tgt=$(q "$HIVE_HOST" "$HADOOP_USER" "SELECT count(*) FROM hw3.sales")
[[ -n $raw && $raw == "$tgt" && $tgt -eq $SALES_ROWS ]] && ok "sales_raw = sales = $tgt" || bad "sales_raw=$raw, sales=$tgt, ожидалось $SALES_ROWS"

log "Partition pruning: какие каталоги читает запрос с фильтром по tx_month"
paths=$(q "$HIVE_HOST" "$HADOOP_USER" "EXPLAIN EXTENDED SELECT region FROM hw3.sales WHERE tx_month='2025-03'" \
  | grep -oE 'location hdfs://[^ ]+/tx_month=[^ ]+' | sort -u || true)
echo "$paths" | sed 's/^/  /'
[[ $(echo "$paths" | grep -c tx_month=) -eq 1 ]] && ok "в план попала одна партиция из 12" || bad "partition pruning не сработал"

log "Несколько клиентов одновременно: 3 параллельные сессии beeline от разных пользователей"
CLIENTS=("$EDGE_HOST:analyst1:2025-01" "$EDGE_HOST:analyst2:2025-06" "$EDGE_HOST:analyst3:2025-12")
tmp=$(mktemp -d)
for c in "${CLIENTS[@]}"; do
  IFS=: read -r host user month <<<"$c"
  (
    t0=$(date +%s)
    r=$(q "$host" "$user" "SELECT logged_in_user(), count(*) FROM hw3.sales WHERE tx_month='$month'" | tail -1)
    echo "$user $month -> ${r:-ошибка}, $(date -d @$t0 +%T)-$(date +%T)" > "$tmp/$user"
  ) &
done
run_on "$HIVE_HOST" > "$tmp/sessions" <<EOF &
max=0
for _ in \$(seq 1 300); do
  n=\$(ss -Htn state established '( sport = :$HIVESERVER2_PORT )' | wc -l)
  (( n > max )) && max=\$n
  (( max > 0 && n == 0 )) && break
  sleep 1
done
echo \$max
EOF
wait
cat "$tmp"/analyst* | sed 's/^/  /'
echo "  максимум одновременных соединений к HiveServer2: $(cat "$tmp/sessions")"
good=$(cat "$tmp"/analyst* | grep -cE -- '-> analyst[0-9],[0-9]+,' || true)
[[ $good -eq ${#CLIENTS[@]} ]] && ok "все ${#CLIENTS[@]} клиента получили ответ" || bad "ответили $good из ${#CLIENTS[@]} клиентов"
[[ $(cat "$tmp/sessions") -ge ${#CLIENTS[@]} ]] 2>/dev/null && ok "сессии были открыты одновременно" || bad "одновременных сессий меньше ${#CLIENTS[@]}"
rm -rf "$tmp"

log "Ошибки в логах Hive (ERROR/FATAL, без AlreadyExistsException от CREATE ... IF NOT EXISTS)"
run_on "$HIVE_HOST" <<<"sudo grep -hE ' (ERROR|FATAL) ' $HIVE_LOG_DIR/hive.log 2>/dev/null | grep -v AlreadyExistsException | wc -l" | sed 's/^/  ERROR\/FATAL строк в hive.log: /'

[[ $fail -eq 0 ]] && log "Hive работает, данные в партиционированной таблице" || die "Проверка не пройдена"
