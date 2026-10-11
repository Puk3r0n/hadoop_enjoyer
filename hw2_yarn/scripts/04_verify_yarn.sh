#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

expected=${#NODEMANAGER_HOSTS[@]}
fail=0
Y="sudo -u $HADOOP_USER -i yarn"

log "Ожидание регистрации NodeManager (до 60 с)"
for _ in $(seq 1 30); do
  n=$(run_on "$EDGE_HOST" <<<"$Y node -list 2>/dev/null | grep -c RUNNING || true")
  [[ $n -ge $expected ]] && break
  sleep 2
done

log "yarn node -list -all"
run_on "$EDGE_HOST" <<<"$Y node -list -all 2>/dev/null" | sed 's/^/  /'
[[ $n -eq $expected ]] && echo "  OK: RUNNING NodeManager $n из $expected" || { echo "  FAIL: RUNNING NodeManager $n из $expected"; fail=1; }

log "Веб-интерфейсы демонов во внутренней сети"
for e in "${UI_ENDPOINTS[@]}"; do
  url="http://$(ui_host "$e"):$(ui_iport "$e")$(ui_path "$e")"
  code=$(run_on "$EDGE_HOST" <<<"curl -s -o /dev/null -w '%{http_code}' -L -m 15 $url")
  if [[ $code == 200 ]]; then
    printf '  OK:   %-24s %s -> %s\n' "$(ui_label "$e")" "$url" "$code"
  else
    printf '  FAIL: %-24s %s -> %s\n' "$(ui_label "$e")" "$url" "$code"; fail=1
  fi
done

log "Опубликованные наружу интерфейсы (через nginx на $EDGE_HOST)"
for e in "${UI_ENDPOINTS[@]}"; do
  path=$(ui_path "$e"); eport=$(ui_eport "$e")
  code=$(run_on "$EDGE_HOST" <<<"curl -s -o /dev/null -w '%{http_code}' -L -m 15 http://127.0.0.1:$eport$path")
  if [[ $code == 200 ]]; then
    printf '  OK:   %-24s http://%s:%s%s -> %s\n' "$(ui_label "$e")" "$EDGE_PUBLIC_IP" "$eport" "$path" "$code"
  else
    printf '  FAIL: %-24s http://%s:%s%s -> %s\n' "$(ui_label "$e")" "$EDGE_PUBLIC_IP" "$eport" "$path" "$code"; fail=1
  fi
done
code=$(run_on "$EDGE_HOST" <<<"curl -s -o /dev/null -w '%{http_code}' -m 15 http://127.0.0.1:$UI_INDEX_PORT/")
[[ $code == 200 ]] && echo "  OK:   Список интерфейсов      http://$EDGE_PUBLIC_IP:$UI_INDEX_PORT/ -> $code" \
  || { echo "  FAIL: Список интерфейсов      -> $code"; fail=1; }

log "Внутренние адреса узлов не должны утекать в опубликованный HTML"
leak=$(run_on "$EDGE_HOST" <<<"curl -s -m 15 http://127.0.0.1:8088/cluster/nodes | grep -oE 'team-09-(nn|00|01):(8042|9864|9870|9868|19888)' | sort -u | wc -l")
[[ $leak -eq 0 ]] && echo "  OK: внутренние host:port в выдаче ResourceManager не найдены" \
  || { echo "  FAIL: внутренние host:port остались в выдаче ($leak шт.) — sub_filter не сработал"; fail=1; }

log "Адреса, на которых слушает ResourceManager"
run_on "$RESOURCEMANAGER_HOST" <<<"ss -ltn | awk 'NR>1{print \$4}' | grep -E ':(8088|8030|8031|8032|8033)\$'" | sed 's/^/  /'

log "Тестовая задача MapReduce: pi (3 map x 1000 сэмплов)"
out=$(run_on "$EDGE_HOST" <<EOF 2>&1
sudo -u $HADOOP_USER -i yarn jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-$HADOOP_VERSION.jar pi 3 1000
EOF
) || true
echo "$out" | grep -E 'Running job|Job job_.* completed|Estimated value of Pi' | sed 's/^/  /'
if echo "$out" | grep -q 'completed successfully'; then
  echo "  OK: задача выполнена"
else
  echo "$out" | tail -20 | sed 's/^/  /'; echo "  FAIL: задача не выполнена"; fail=1
fi

log "Последняя задача в JobHistory Server"
run_on "$EDGE_HOST" <<EOF | sed 's/^/  /'
curl -s http://$JOBHISTORY_HOST:19888/ws/v1/history/mapreduce/jobs \
  | python3 -c 'import json,sys; j=json.load(sys.stdin)["jobs"]["job"][-1]; print(j["id"], j["name"], j["state"], "maps:", j["mapsCompleted"], "reduces:", j["reducesCompleted"])'
EOF

log "Ошибки в логах YARN (ERROR/FATAL, без штатных сообщений об остановке)"
for host in $(all_hosts); do
  c=$(run_on "$host" <<<"sudo grep -hE ' (ERROR|FATAL) ' $HADOOP_LOG_DIR/hadoop-$HADOOP_USER-{resourcemanager,nodemanager,historyserver}-*.log 2>/dev/null | grep -vE '$SHUTDOWN_NOISE' | wc -l")
  echo "  [$host] ERROR/FATAL строк: $c"
done

[[ $fail -eq 0 ]] && log "YARN работает, интерфейсы опубликованы" || die "Проверка не пройдена"
