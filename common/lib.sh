#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${INVENTORY:-$REPO_ROOT/inventory.env}"

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

SHUTDOWN_NOISE='RECEIVED SIGNAL 15|InterruptedException|interrupted'

log() { echo -e "\033[1;34m[$(date +%H:%M:%S)]\033[0m $*"; }
die() { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }

host_ip() {
  local h=$1 n
  for n in "${NODES[@]}"; do [[ ${n%%:*} == "$h" ]] && { echo "${n#*:}"; return; }; done
  die "host $h not in inventory"
}
all_hosts() { local n; for n in "${NODES[@]}"; do echo "${n%%:*}"; done; }
is_local() { [[ $1 == "$(hostname -s)" ]]; }

ui_label() { echo "$1" | cut -d: -f1; }
ui_host()  { echo "$1" | cut -d: -f2; }
ui_iport() { echo "$1" | cut -d: -f3; }
ui_eport() { echo "$1" | cut -d: -f4; }
ui_path()  { echo "$1" | cut -d: -f5; }

run_on() {
  local host=$1; shift
  if is_local "$host"; then bash -s "$@"; else ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" bash -s "$@"; fi
}

copy_to() {
  local host=$1 src=$2 dst=$3
  if is_local "$host"; then cp "$src" "$dst"; else scp -q "${SSH_OPTS[@]}" "$src" "$SSH_USER@$host:$dst"; fi
}

start_daemon() {
  local host=$1 cmd=$2 daemon=$3
  run_on "$host" <<EOF
set -e
if pgrep -u $HADOOP_USER -f "proc_$daemon( |\$)" >/dev/null; then
  echo "  [$host] $daemon уже запущен"
else
  sudo -u $HADOOP_USER -i $HADOOP_HOME/bin/$cmd --daemon start $daemon
  sleep 3
  pgrep -u $HADOOP_USER -f "proc_$daemon( |\$)" >/dev/null \
    || { echo "  [$host] $daemon не стартовал, см. $HADOOP_LOG_DIR"; exit 1; }
  echo "  [$host] $daemon запущен"
fi
EOF
}

stop_daemon() {
  local host=$1 cmd=$2 daemon=$3
  run_on "$host" <<EOF
sudo -u $HADOOP_USER -i $HADOOP_HOME/bin/$cmd --daemon stop $daemon 2>/dev/null && echo "  [$host] $daemon остановлен" || echo "  [$host] $daemon не был запущен"
EOF
}

push_configs() {
  local dir=$1 host f
  for host in $(all_hosts); do
    log "Конфиги -> $host"
    run_on "$host" <<<"rm -rf /tmp/hadoop-conf && mkdir -p /tmp/hadoop-conf"
    for f in "$dir"/*; do copy_to "$host" "$f" "/tmp/hadoop-conf/$(basename "$f")"; done
    run_on "$host" <<EOF
set -e
sudo cp /tmp/hadoop-conf/* $HADOOP_HOME/etc/hadoop/
sudo chown -R $HADOOP_USER:$HADOOP_USER $HADOOP_HOME/etc/hadoop
rm -rf /tmp/hadoop-conf
EOF
  done
}

prop() { printf '  <property>\n    <name>%s</name>\n    <value>%s</value>\n  </property>\n' "$1" "$2"; }
xml_header() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>\n<configuration>\n'; }
xml_footer() { printf '</configuration>\n'; }
