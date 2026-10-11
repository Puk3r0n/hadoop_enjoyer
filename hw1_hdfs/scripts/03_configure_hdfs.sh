#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT

{
  xml_header
  prop fs.defaultFS "hdfs://$NAMENODE_HOST:$HDFS_PORT"
  prop hadoop.tmp.dir "$HADOOP_DATA_DIR/tmp"
  xml_footer
} > "$CONF/core-site.xml"

{
  xml_header
  prop dfs.replication "$DFS_REPLICATION"
  prop dfs.namenode.name.dir "file://$HADOOP_DATA_DIR/namenode"
  prop dfs.datanode.data.dir "file://$HADOOP_DATA_DIR/datanode"
  prop dfs.namenode.checkpoint.dir "file://$HADOOP_DATA_DIR/namesecondary"
  prop dfs.namenode.http-address "$NAMENODE_HOST:9870"
  prop dfs.namenode.secondary.http-address "$SECONDARY_NAMENODE_HOST:9868"
  prop dfs.hosts "$HADOOP_HOME/etc/hadoop/workers"
  prop dfs.permissions.superusergroup "$HADOOP_USER"
  xml_footer
} > "$CONF/hdfs-site.xml"

printf '%s\n' "${DATANODE_HOSTS[@]}" > "$CONF/workers"

push_configs "$CONF"

for host in $(all_hosts); do
  run_on "$host" <<EOF
set -e
F=$HADOOP_HOME/etc/hadoop/hadoop-env.sh
sudo sed -i '/# BEGIN hadoop_hw/,/# END hadoop_hw/d' \$F
sudo tee -a \$F >/dev/null <<'ENV'
# BEGIN hadoop_hw
export JAVA_HOME=$JAVA_HOME
export HADOOP_LOG_DIR=$HADOOP_LOG_DIR
export HADOOP_PID_DIR=$HADOOP_DATA_DIR/pids
export HDFS_NAMENODE_OPTS="-Xmx512m"
export HDFS_SECONDARYNAMENODE_OPTS="-Xmx256m"
export HDFS_DATANODE_OPTS="-Xmx256m"
export YARN_RESOURCEMANAGER_OPTS="-Xmx512m"
export YARN_NODEMANAGER_OPTS="-Xmx256m"
export MAPRED_HISTORYSERVER_OPTS="-Xmx256m"
# END hadoop_hw
ENV
EOF
done
log "Конфигурация HDFS разослана"
