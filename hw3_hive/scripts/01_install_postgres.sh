#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

if [[ ! -s $METASTORE_DB_PASSWORD_FILE ]]; then
  log "Генерирую пароль БД metastore в $METASTORE_DB_PASSWORD_FILE"
  mkdir -p "$(dirname "$METASTORE_DB_PASSWORD_FILE")"
  (umask 077; openssl rand -hex 16 > "$METASTORE_DB_PASSWORD_FILE")
fi
DB_PASSWORD=$(cat "$METASTORE_DB_PASSWORD_FILE")

log "PostgreSQL для metastore на $HIVE_HOST"
run_on "$HIVE_HOST" <<EOF
set -e
export DEBIAN_FRONTEND=noninteractive
if ! dpkg -s postgresql >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq postgresql >/dev/null
fi
sudo systemctl enable --now postgresql >/dev/null 2>&1

P="sudo -u postgres psql -v ON_ERROR_STOP=1 -qtA"
if [[ \$(\$P -c "SELECT 1 FROM pg_roles WHERE rolname='$METASTORE_DB_USER'") != 1 ]]; then
  \$P -c "CREATE ROLE $METASTORE_DB_USER LOGIN"
fi
\$P -c "ALTER ROLE $METASTORE_DB_USER PASSWORD '$DB_PASSWORD'" >/dev/null
if [[ \$(\$P -c "SELECT 1 FROM pg_database WHERE datname='$METASTORE_DB_NAME'") != 1 ]]; then
  \$P -c "CREATE DATABASE $METASTORE_DB_NAME OWNER $METASTORE_DB_USER"
fi
echo "  [\$(hostname)] \$(\$P -c 'SELECT version()' | cut -d' ' -f1-2), база $METASTORE_DB_NAME, владелец $METASTORE_DB_USER"
echo "  [\$(hostname)] слушает: \$(ss -ltn | awk '\$4 ~ /:5432\$/ {print \$4}' | tr '\n' ' ')"
EOF
log "PostgreSQL готов"
