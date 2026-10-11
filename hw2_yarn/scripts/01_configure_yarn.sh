#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT

{
  xml_header
  prop yarn.resourcemanager.hostname "$RESOURCEMANAGER_HOST"
  prop yarn.nodemanager.aux-services "mapreduce_shuffle"
  prop yarn.nodemanager.aux-services.mapreduce_shuffle.class "org.apache.hadoop.mapred.ShuffleHandler"
  prop yarn.nodemanager.resource.memory-mb "$NODEMANAGER_MEMORY_MB"
  prop yarn.nodemanager.resource.cpu-vcores "$NODEMANAGER_VCORES"
  prop yarn.scheduler.minimum-allocation-mb "$CONTAINER_MIN_MB"
  prop yarn.scheduler.maximum-allocation-mb "$CONTAINER_MAX_MB"
  prop yarn.nodemanager.vmem-check-enabled "false"
  prop yarn.nodemanager.local-dirs "$HADOOP_DATA_DIR/yarn/local"
  prop yarn.nodemanager.log-dirs "$HADOOP_LOG_DIR/yarn-containers"
  prop yarn.nodemanager.env-whitelist "JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME"
  prop yarn.log-aggregation-enable "true"
  prop yarn.nodemanager.remote-app-log-dir "/app-logs"
  prop yarn.log.server.url "http://$JOBHISTORY_HOST:19888/jobhistory/logs"
  xml_footer
} > "$CONF/yarn-site.xml"

{
  xml_header
  prop mapreduce.framework.name "yarn"
  prop yarn.app.mapreduce.am.env "HADOOP_MAPRED_HOME=$HADOOP_HOME"
  prop mapreduce.map.env "HADOOP_MAPRED_HOME=$HADOOP_HOME"
  prop mapreduce.reduce.env "HADOOP_MAPRED_HOME=$HADOOP_HOME"
  prop yarn.app.mapreduce.am.resource.mb "512"
  prop yarn.app.mapreduce.am.command-opts "-Xmx410m"
  prop mapreduce.map.memory.mb "512"
  prop mapreduce.map.java.opts "-Xmx410m"
  prop mapreduce.reduce.memory.mb "512"
  prop mapreduce.reduce.java.opts "-Xmx410m"
  prop mapreduce.jobhistory.address "$JOBHISTORY_HOST:10020"
  prop mapreduce.jobhistory.webapp.address "$JOBHISTORY_HOST:19888"
  prop mapreduce.jobhistory.intermediate-done-dir "/mr-history/tmp"
  prop mapreduce.jobhistory.done-dir "/mr-history/done"
  xml_footer
} > "$CONF/mapred-site.xml"

push_configs "$CONF"

for host in "${NODEMANAGER_HOSTS[@]}"; do
  run_on "$host" <<EOF
sudo mkdir -p $HADOOP_DATA_DIR/yarn/local $HADOOP_LOG_DIR/yarn-containers
sudo chown -R $HADOOP_USER:$HADOOP_USER $HADOOP_DATA_DIR/yarn $HADOOP_LOG_DIR/yarn-containers
EOF
done
log "Конфигурация YARN разослана"
