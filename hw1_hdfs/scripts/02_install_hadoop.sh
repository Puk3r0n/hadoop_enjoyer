#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

TARBALL="hadoop-$HADOOP_VERSION.tar.gz"
CACHE_DIR="$HOME/hadoop-dist"
mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

if [[ ! -f $TARBALL ]]; then
  log "Скачиваю $TARBALL"
  curl -fL --progress-bar -o "$TARBALL.part" "$HADOOP_MIRROR/hadoop-$HADOOP_VERSION/$TARBALL"
  mv "$TARBALL.part" "$TARBALL"
fi

log "Проверка sha512"
curl -fsSL -o "$TARBALL.sha512" "$HADOOP_CHECKSUM_URL/hadoop-$HADOOP_VERSION/$TARBALL.sha512"
expected=$(grep -oiE '[0-9a-f]{128}' "$TARBALL.sha512" | head -1 | tr 'A-F' 'a-f')
actual=$(sha512sum "$TARBALL" | awk '{print $1}')
[[ $expected == "$actual" ]] || { rm -f "$TARBALL"; die "sha512 не совпал, архив удалён — перезапустите скрипт"; }
log "sha512 OK"

for host in $(all_hosts); do
  log "Установка на $host"
  if run_on "$host" <<<"test -x /opt/hadoop-$HADOOP_VERSION/bin/hdfs"; then
    echo "  [$host] hadoop-$HADOOP_VERSION уже установлен"
  else
    copy_to "$host" "$CACHE_DIR/$TARBALL" "/tmp/$TARBALL"
    run_on "$host" <<EOF
set -e
sudo tar -xzf /tmp/$TARBALL -C /opt
rm -f /tmp/$TARBALL
EOF
  fi
  run_on "$host" <<EOF
set -e
sudo ln -sfn /opt/hadoop-$HADOOP_VERSION $HADOOP_HOME
sudo chown -R $HADOOP_USER:$HADOOP_USER /opt/hadoop-$HADOOP_VERSION
sudo tee /etc/profile.d/hadoop.sh >/dev/null <<'PROFILE'
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=\$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
PROFILE
echo "  [\$(hostname)] \$(sudo -u $HADOOP_USER -i $HADOOP_HOME/bin/hadoop version | head -1)"
EOF
done
log "Hadoop $HADOOP_VERSION установлен"
