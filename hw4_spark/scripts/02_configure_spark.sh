#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

NN="hdfs://$NAMENODE_HOST:$HDFS_PORT"
CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT

cat > "$CONF/spark-defaults.conf" <<EOF
# BEGIN hadoop_hw
spark.master                              yarn
spark.submit.deployMode                   client
spark.driver.memory                       $SPARK_DRIVER_MEMORY
spark.yarn.am.memory                      $SPARK_AM_MEMORY
spark.executor.memory                     $SPARK_EXECUTOR_MEMORY
spark.executor.cores                      $SPARK_EXECUTOR_CORES
spark.executor.instances                  $SPARK_EXECUTOR_INSTANCES
spark.yarn.archive                        $NN$SPARK_YARN_ARCHIVE
spark.eventLog.enabled                    true
spark.eventLog.dir                        $NN$SPARK_EVENT_LOG_DIR
spark.sql.catalogImplementation           hive
spark.sql.warehouse.dir                   $NN$HIVE_WAREHOUSE_DIR
spark.sql.sources.partitionOverwriteMode  dynamic
spark.sql.parquet.writeLegacyFormat       true
spark.sql.shuffle.partitions              8
spark.pyspark.python                      python3
# END hadoop_hw
EOF

cat > "$CONF/spark-env.sh" <<EOF
# BEGIN hadoop_hw
export JAVA_HOME=$JAVA_HOME
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export SPARK_LOG_DIR=$SPARK_LOG_DIR
# END hadoop_hw
EOF

{
  xml_header
  prop hive.metastore.uris "thrift://$HIVE_HOST:$HIVE_METASTORE_PORT"
  prop hive.metastore.warehouse.dir "$HIVE_WAREHOUSE_DIR"
  xml_footer
} > "$CONF/hive-site.xml"

cat > "$CONF/log4j2.properties" <<'EOF'
rootLogger.level = warn
rootLogger.appenderRef.stdout.ref = console
appender.console.type = Console
appender.console.name = console
appender.console.target = SYSTEM_ERR
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = %d{HH:mm:ss} %p %c{1}: %m%n
logger.yarn.name = org.apache.spark.deploy.yarn.Client
logger.yarn.level = info
EOF

log "Конфиги Spark -> $SPARK_HOST"
run_on "$SPARK_HOST" <<<"rm -rf /tmp/spark-conf && mkdir -p /tmp/spark-conf"
for f in "$CONF"/*; do copy_to "$SPARK_HOST" "$f" "/tmp/spark-conf/$(basename "$f")"; done
run_on "$SPARK_HOST" <<EOF
set -e
sudo cp /tmp/spark-conf/* $SPARK_HOME/conf/
sudo chown -R $HADOOP_USER:$HADOOP_USER $SPARK_HOME/conf
rm -rf /tmp/spark-conf
EOF

log "Каталоги Spark в HDFS и архив jar-файлов для YARN"
run_on "$SPARK_HOST" <<EOF
set -e
H="sudo -u $HADOOP_USER -i hdfs dfs"
\$H -mkdir -p $SPARK_EVENT_LOG_DIR $(dirname "$SPARK_YARN_ARCHIVE")
\$H -chmod 1777 $SPARK_EVENT_LOG_DIR
if \$H -test -e $SPARK_YARN_ARCHIVE; then
  echo "  $SPARK_YARN_ARCHIVE уже есть"
else
  tmp=\$(mktemp -d) && chmod 755 \$tmp
  (cd $SPARK_HOME/jars && python3 -m zipfile -c \$tmp/jars.zip *.jar)
  chmod 644 \$tmp/jars.zip
  \$H -put \$tmp/jars.zip $SPARK_YARN_ARCHIVE
  rm -rf \$tmp
  echo "  $SPARK_YARN_ARCHIVE загружен"
fi
\$H -ls $SPARK_YARN_ARCHIVE | tail -1 | awk '{print "  " \$5 " байт  " \$8}'
EOF
log "Конфигурация Spark готова"
