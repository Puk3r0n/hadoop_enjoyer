#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

TARBALL="apache-hive-$HIVE_VERSION-bin.tar.gz"
CACHE_DIR="$HOME/hadoop-dist"
mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

if [[ ! -f $TARBALL ]]; then
  log "Скачиваю $TARBALL"
  curl -fL --progress-bar -o "$TARBALL.part" "$HIVE_MIRROR/hive-$HIVE_VERSION/$TARBALL"
  mv "$TARBALL.part" "$TARBALL"
fi

log "Проверка sha256"
curl -fsSL -o "$TARBALL.sha256" "$HIVE_MIRROR/hive-$HIVE_VERSION/$TARBALL.sha256"
expected=$(grep -oiE '[0-9a-f]{64}' "$TARBALL.sha256" | head -1 | tr 'A-F' 'a-f')
actual=$(sha256sum "$TARBALL" | awk '{print $1}')
[[ $expected == "$actual" ]] || { rm -f "$TARBALL"; die "sha256 не совпал, архив удалён — перезапустите скрипт"; }
log "sha256 OK"

log "Установка на $HIVE_HOST"
if run_on "$HIVE_HOST" <<<"test -x /opt/apache-hive-$HIVE_VERSION-bin/bin/hive"; then
  echo "  [$HIVE_HOST] apache-hive-$HIVE_VERSION уже установлен"
else
  copy_to "$HIVE_HOST" "$CACHE_DIR/$TARBALL" "/tmp/$TARBALL"
  run_on "$HIVE_HOST" <<EOF
set -e
sudo tar -xzf /tmp/$TARBALL -C /opt
rm -f /tmp/$TARBALL
EOF
fi

run_on "$HIVE_HOST" <<EOF
set -e
H=/opt/apache-hive-$HIVE_VERSION-bin
ls \$H/lib/postgresql-*.jar >/dev/null || { echo "  в \$H/lib нет JDBC-драйвера PostgreSQL"; exit 1; }

hadoop_guava=\$(ls $HADOOP_HOME/share/hadoop/common/lib/guava-*.jar | head -1)
for g in \$H/lib/guava-*.jar; do
  [[ \$(basename \$g) == \$(basename \$hadoop_guava) ]] || sudo mv \$g \$g.disabled
done
[[ -f \$H/lib/\$(basename \$hadoop_guava) ]] || sudo cp \$hadoop_guava \$H/lib/

sudo mkdir -p \$H/auxlib
sudo cp \$H/lib/commons-collections-3.*.jar \$H/auxlib/

sudo ln -sfn \$H $HIVE_HOME
sudo chown -R $HADOOP_USER:$HADOOP_USER \$H
sudo mkdir -p $HIVE_LOG_DIR $HADOOP_DATA_DIR/hive
sudo chown -R $HADOOP_USER:$HADOOP_USER $HIVE_LOG_DIR $HADOOP_DATA_DIR/hive
sudo tee /etc/profile.d/hive.sh >/dev/null <<'PROFILE'
export HIVE_HOME=$HIVE_HOME
export HIVE_CONF_DIR=$HIVE_HOME/conf
export PATH=\$PATH:$HIVE_HOME/bin
PROFILE
echo "  [\$(hostname)] \$(sudo -u $HADOOP_USER -i $HIVE_HOME/bin/hive --version 2>/dev/null | head -1), guava: \$(basename \$hadoop_guava), jdbc: \$(basename \$H/lib/postgresql-*.jar)"
EOF
log "Hive $HIVE_VERSION установлен"
