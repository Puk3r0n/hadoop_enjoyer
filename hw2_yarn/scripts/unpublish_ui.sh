#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"
run_on "$EDGE_HOST" <<'EOF'
set -e
sudo rm -f /etc/nginx/sites-enabled/hadoop-ui
sudo systemctl reload nginx 2>/dev/null || sudo systemctl stop nginx
echo "  публикация интерфейсов отключена"
EOF
