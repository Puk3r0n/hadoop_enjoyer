#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

[[ -s $METASTORE_DB_PASSWORD_FILE ]] || die "нет $METASTORE_DB_PASSWORD_FILE — сначала 01_install_postgres.sh"
DB_PASSWORD=$(cat "$METASTORE_DB_PASSWORD_FILE")

CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT

{
  xml_header
  prop javax.jdo.option.ConnectionURL "jdbc:postgresql://localhost:5432/$METASTORE_DB_NAME"
  prop javax.jdo.option.ConnectionDriverName "org.postgresql.Driver"
  prop javax.jdo.option.ConnectionUserName "$METASTORE_DB_USER"
  prop javax.jdo.option.ConnectionPassword "$DB_PASSWORD"
  prop hive.metastore.uris "thrift://$HIVE_HOST:$HIVE_METASTORE_PORT"
  prop hive.metastore.port "$HIVE_METASTORE_PORT"
  prop hive.metastore.warehouse.dir "$HIVE_WAREHOUSE_DIR"
  prop hive.metastore.schema.verification "true"
  prop hive.metastore.event.db.notification.api.auth "false"
  prop hive.server2.thrift.bind.host "$HIVE_HOST"
  prop hive.server2.thrift.port "$HIVESERVER2_PORT"
  prop hive.server2.webui.host "$HIVE_HOST"
  prop hive.server2.webui.port "$HIVESERVER2_UI_PORT"
  prop hive.server2.enable.doAs "false"
  prop hive.server2.logging.operation.log.location "$HADOOP_DATA_DIR/hive/operation_logs"
  prop hive.exec.scratchdir "/tmp/hive"
  prop hive.exec.local.scratchdir "$HADOOP_DATA_DIR/hive/scratch"
  prop hive.downloaded.resources.dir "$HADOOP_DATA_DIR/hive/resources"
  prop hive.querylog.location "$HIVE_LOG_DIR"
  prop hive.execution.engine "mr"
  prop hive.exec.dynamic.partition "true"
  prop hive.exec.dynamic.partition.mode "nonstrict"
  prop hive.support.concurrency "false"
  prop hive.stats.autogather "true"
  xml_footer
} > "$CONF/hive-site.xml"

cat > "$CONF/hive-env.sh" <<EOF
# BEGIN hadoop_hw
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HIVE_CONF_DIR=$HIVE_HOME/conf
export HIVE_LOG_DIR=$HIVE_LOG_DIR
case "\$SERVICE" in
  metastore)   export HADOOP_HEAPSIZE=$HIVE_METASTORE_HEAP_MB ;;
  hiveserver2) export HADOOP_HEAPSIZE=$HIVESERVER2_HEAP_MB ;;
  *)           export HADOOP_HEAPSIZE=512 ;;
esac
# END hadoop_hw
EOF

sed "s|^property.hive.log.dir = .*|property.hive.log.dir = $HIVE_LOG_DIR|" \
  <(run_on "$HIVE_HOST" <<<"cat $HIVE_HOME/conf/hive-log4j2.properties.template") > "$CONF/hive-log4j2.properties"

log "Конфиги Hive -> $HIVE_HOST"
run_on "$HIVE_HOST" <<<"rm -rf /tmp/hive-conf && mkdir -p /tmp/hive-conf"
for f in "$CONF"/*; do copy_to "$HIVE_HOST" "$f" "/tmp/hive-conf/$(basename "$f")"; done
run_on "$HIVE_HOST" <<EOF
set -e
sudo cp /tmp/hive-conf/* $HIVE_HOME/conf/
sudo chown -R $HADOOP_USER:$HADOOP_USER $HIVE_HOME/conf
sudo chmod 640 $HIVE_HOME/conf/hive-site.xml
rm -rf /tmp/hive-conf
sudo -u $HADOOP_USER mkdir -p $HADOOP_DATA_DIR/hive/{operation_logs,scratch,resources}
EOF

log "Каталоги Hive в HDFS"
run_on "$EDGE_HOST" <<EOF
set -e
H="sudo -u $HADOOP_USER -i hdfs dfs"
\$H -mkdir -p /tmp/hive $HIVE_WAREHOUSE_DIR
\$H -chmod 1777 /tmp/hive
\$H -chmod g+w $HIVE_WAREHOUSE_DIR
echo "  /tmp/hive и $HIVE_WAREHOUSE_DIR готовы"
EOF

log "Доля памяти под ApplicationMaster в YARN: $YARN_MAX_AM_RESOURCE_PERCENT"
run_on "$RESOURCEMANAGER_HOST" <<EOF
set -e
F=$HADOOP_HOME/etc/hadoop/capacity-scheduler.xml
sudo sed -i '/<name>yarn.scheduler.capacity.maximum-am-resource-percent<\/name>/{n;s|<value>[^<]*</value>|<value>$YARN_MAX_AM_RESOURCE_PERCENT</value>|}' \$F
grep -A1 maximum-am-resource-percent \$F | grep -oE '<value>[^<]+' | sed 's/<value>/  maximum-am-resource-percent = /'
sudo -u $HADOOP_USER -i yarn rmadmin -refreshQueues 2>/dev/null && echo "  очереди YARN перечитаны"
EOF

log "Схема metastore в PostgreSQL (если ещё не создана)"
run_on "$HIVE_HOST" <<EOF
set -e
S="sudo -u $HADOOP_USER -i $HIVE_HOME/bin/schematool -dbType postgres"
if \$S -info >/tmp/schematool_info.log 2>&1; then
  echo "  схема уже создана: \$(grep -E 'Metastore schema version' /tmp/schematool_info.log | tail -1)"
else
  \$S -initSchema 2>&1 | grep -E 'Initialization script|schemaTool completed|Error' | sed 's/^/  /'
  \$S -info 2>&1 | grep -E 'Metastore schema version' | sed 's/^/  /'
fi
rm -f /tmp/schematool_info.log
EOF
log "Конфигурация Hive готова"
