#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

TARBALL="$SPARK_PACKAGE.tgz"
CACHE_DIR="$HOME/hadoop-dist"
mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

if [[ ! -f $TARBALL ]]; then
  log "Скачиваю $TARBALL"
  curl -fL --progress-bar -o "$TARBALL.part" "$SPARK_MIRROR/spark-$SPARK_VERSION/$TARBALL"
  mv "$TARBALL.part" "$TARBALL"
fi

log "Проверка sha512"
curl -fsSL -o "$TARBALL.sha512" "$SPARK_CHECKSUM_URL/spark-$SPARK_VERSION/$TARBALL.sha512"
expected=$(grep -oiE '[0-9a-f]{128}' "$TARBALL.sha512" | head -1 | tr 'A-F' 'a-f')
actual=$(sha512sum "$TARBALL" | awk '{print $1}')
[[ $expected == "$actual" ]] || { rm -f "$TARBALL"; die "sha512 не совпал, архив удалён — перезапустите скрипт"; }
log "sha512 OK"

log "Установка на $SPARK_HOST"
if run_on "$SPARK_HOST" <<<"test -x /opt/$SPARK_PACKAGE/bin/spark-submit"; then
  echo "  [$SPARK_HOST] $SPARK_PACKAGE уже установлен"
else
  copy_to "$SPARK_HOST" "$CACHE_DIR/$TARBALL" "/tmp/$TARBALL"
  run_on "$SPARK_HOST" <<EOF
set -e
sudo tar -xzf /tmp/$TARBALL -C /opt
rm -f /tmp/$TARBALL
EOF
fi

run_on "$SPARK_HOST" <<EOF
set -e
sudo ln -sfn /opt/$SPARK_PACKAGE $SPARK_HOME
sudo chown -R $HADOOP_USER:$HADOOP_USER /opt/$SPARK_PACKAGE
sudo mkdir -p $SPARK_LOG_DIR
sudo chown -R $HADOOP_USER:$HADOOP_USER $SPARK_LOG_DIR
sudo tee /etc/profile.d/spark.sh >/dev/null <<'PROFILE'
export SPARK_HOME=$SPARK_HOME
export PATH=\$PATH:$SPARK_HOME/bin
PROFILE
echo "  [\$(hostname)] Spark \$(sudo -u $HADOOP_USER -i $SPARK_HOME/bin/spark-submit --version 2>&1 | grep -m1 -oE 'version [0-9.]+'), встроенный клиент metastore: \$(basename \$(ls $SPARK_HOME/jars/hive-metastore-*.jar))"
EOF
log "Spark $SPARK_VERSION установлен"
