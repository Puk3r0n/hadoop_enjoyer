#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

log "Prefect $PREFECT_VERSION -> $SPARK_HOST:$PREFECT_VENV"
run_on "$SPARK_HOST" <<EOF2
set -e
command -v python3 >/dev/null
python3 -c 'import ensurepip' 2>/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv >/dev/null
if [ ! -x $PREFECT_VENV/bin/prefect ] || ! $PREFECT_VENV/bin/prefect version 2>/dev/null | grep -q "$PREFECT_VERSION"; then
  sudo rm -rf $PREFECT_VENV
  sudo python3 -m venv $PREFECT_VENV
  sudo $PREFECT_VENV/bin/pip install -q --upgrade pip
  sudo $PREFECT_VENV/bin/pip install -q "prefect==$PREFECT_VERSION"
fi
sudo mkdir -p $PREFECT_HOME_DIR $PREFECT_LOG_DIR
sudo chown -R $HADOOP_USER:$HADOOP_USER $PREFECT_HOME_DIR $PREFECT_LOG_DIR
$PREFECT_VENV/bin/prefect version | sed 's/^/  /' | head -4
EOF2
