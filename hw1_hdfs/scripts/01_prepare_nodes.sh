#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

HOSTS_BLOCK=""
for n in "${NODES[@]}"; do HOSTS_BLOCK+="${n#*:} ${n%%:*}"$'\n'; done

for host in $(all_hosts); do
  log "Подготовка $host"
  run_on "$host" <<EOF
set -e
export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s $JAVA_PACKAGE >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq $JAVA_PACKAGE >/dev/null
fi
test -x $JAVA_HOME/bin/java || { echo "JAVA_HOME=$JAVA_HOME не найден"; exit 1; }

id $HADOOP_USER >/dev/null 2>&1 || sudo useradd -m -s /bin/bash $HADOOP_USER

sudo sed -i -E 's/^(127\.0\.1\.1[[:space:]].*)\$/# \1  # hadoop_hw/' /etc/hosts
sudo sed -i '/# BEGIN hadoop_hw/,/# END hadoop_hw/d' /etc/hosts
printf '# BEGIN hadoop_hw\n%s# END hadoop_hw\n' "$HOSTS_BLOCK" | sudo tee -a /etc/hosts >/dev/null

sudo mkdir -p $HADOOP_DATA_DIR/pids $HADOOP_LOG_DIR
sudo chown -R $HADOOP_USER:$HADOOP_USER $HADOOP_DATA_DIR $HADOOP_LOG_DIR

echo "  [\$(hostname)] java: \$($JAVA_HOME/bin/java -version 2>&1 | head -1); \$(getent hosts \$(hostname))"
EOF
done
log "Узлы подготовлены"
