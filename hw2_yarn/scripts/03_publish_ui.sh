#!/usr/bin/env bash
source "$(dirname "$0")/../../common/lib.sh"

SITE_NAME="hadoop-ui"
CONF=$(mktemp)
INDEX=$(mktemp)
trap 'rm -f "$CONF" "$INDEX"' EXIT

emit_subfilters() {
  local e
  for e in "${UI_ENDPOINTS[@]}"; do
    printf '        sub_filter "%s:%s" "%s:%s";\n' \
      "$(ui_host "$e")" "$(ui_iport "$e")" "$EDGE_PUBLIC_IP" "$(ui_eport "$e")"
  done
}

SUBFILTERS=$(emit_subfilters)

{
  for e in "${UI_ENDPOINTS[@]}"; do
    host=$(ui_host "$e"); iport=$(ui_iport "$e"); eport=$(ui_eport "$e")
    cat <<NGX
server {
    listen $eport;
    server_name _;

    location / {
        proxy_pass http://$host:$iport;
        proxy_http_version 1.1;
        proxy_set_header Host $host:$iport;
        proxy_set_header Accept-Encoding "";
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 10s;
        proxy_read_timeout 300s;
        proxy_redirect http://$host:$iport/ /;
        sub_filter_once off;
        sub_filter_types *;
$SUBFILTERS
    }
}

NGX
  done

  cat <<NGX
server {
    listen $UI_INDEX_PORT default_server;
    server_name _;
    root /var/www/$SITE_NAME;
    index index.html;
}
NGX
} > "$CONF"

{
  cat <<'HTML'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>Hadoop cluster UI</title>
<style>
body{font-family:system-ui,sans-serif;margin:3rem auto;max-width:48rem;line-height:1.5}
table{border-collapse:collapse;width:100%}
th,td{border-bottom:1px solid #ddd;padding:.5rem .4rem;text-align:left}
code{background:#f4f4f4;padding:.1rem .3rem;border-radius:3px}
</style>
</head>
<body>
<h1>Веб-интерфейсы кластера Hadoop</h1>
<table>
<tr><th>Демон</th><th>Узел кластера</th><th>Внешний адрес</th></tr>
HTML
  for e in "${UI_ENDPOINTS[@]}"; do
    printf '<tr><td>%s</td><td><code>%s:%s</code></td><td><a href="http://%s:%s%s">%s:%s</a></td></tr>\n' \
      "$(ui_label "$e")" "$(ui_host "$e")" "$(ui_iport "$e")" \
      "$EDGE_PUBLIC_IP" "$(ui_eport "$e")" "$(ui_path "$e")" \
      "$EDGE_PUBLIC_IP" "$(ui_eport "$e")"
  done
  cat <<'HTML'
</table>
</body>
</html>
HTML
} > "$INDEX"

log "Установка nginx на $EDGE_HOST"
run_on "$EDGE_HOST" <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
if ! dpkg -s nginx >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq nginx >/dev/null
fi
dpkg -s libnginx-mod-http-sub-filter >/dev/null 2>&1 || true
nginx -V 2>&1 | tr ' ' '\n' | grep -q -- '--with-http_sub_module' \
  || { echo "nginx собран без http_sub_module"; exit 1; }
EOF

log "Публикация конфигурации"
copy_to "$EDGE_HOST" "$CONF" "/tmp/$SITE_NAME.conf"
copy_to "$EDGE_HOST" "$INDEX" "/tmp/$SITE_NAME.html"
run_on "$EDGE_HOST" <<EOF
set -e
sudo mkdir -p /var/www/$SITE_NAME
sudo chmod 755 /var/www/$SITE_NAME
sudo cp /tmp/$SITE_NAME.html /var/www/$SITE_NAME/index.html
sudo chmod 644 /var/www/$SITE_NAME/index.html
sudo cp /tmp/$SITE_NAME.conf /etc/nginx/sites-available/$SITE_NAME
sudo chmod 644 /etc/nginx/sites-available/$SITE_NAME
sudo ln -sfn /etc/nginx/sites-available/$SITE_NAME /etc/nginx/sites-enabled/$SITE_NAME
sudo rm -f /etc/nginx/sites-enabled/default
rm -f /tmp/$SITE_NAME.conf /tmp/$SITE_NAME.html
sudo nginx -t
sudo systemctl enable nginx >/dev/null 2>&1
sudo systemctl reload nginx 2>/dev/null || sudo systemctl restart nginx
EOF

log "Опубликованные адреса"
printf '  %-24s %s\n' "Список интерфейсов" "http://$EDGE_PUBLIC_IP:$UI_INDEX_PORT/"
for e in "${UI_ENDPOINTS[@]}"; do
  printf '  %-24s http://%s:%s%s\n' "$(ui_label "$e")" "$EDGE_PUBLIC_IP" "$(ui_eport "$e")" "$(ui_path "$e")"
done
log "Интерфейсы опубликованы. Проверка: $(dirname "$0")/04_verify_yarn.sh"
