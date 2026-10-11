#!/usr/bin/env bash
set -euo pipefail

EDGE_SSH=${EDGE_SSH:-team@171.22.73.198}
EDGE_KEY=${EDGE_KEY:-}
SOCKS_PORT=${SOCKS_PORT:-1080}

PORTS=(9870 9868 9864 9865 9866 8088 8042 8043 8044 19888 80)

FORWARDS=()
for p in "${PORTS[@]}"; do
  if [[ $p == 80 ]]; then
    FORWARDS+=(-L "8080:127.0.0.1:80")
  else
    FORWARDS+=(-L "$p:127.0.0.1:$p")
  fi
done

KEY_OPT=()
[[ -n $EDGE_KEY ]] && KEY_OPT=(-i "$EDGE_KEY" -o IdentitiesOnly=yes)

cat <<TXT
Туннель к веб-интерфейсам кластера через edge-ноду.

Список интерфейсов:  http://127.0.0.1:8080/
NameNode:            http://127.0.0.1:9870/dfshealth.html
SecondaryNameNode:   http://127.0.0.1:9868/status.html
ResourceManager:     http://127.0.0.1:8088/cluster
JobHistory:          http://127.0.0.1:19888/jobhistory
DataNode:            http://127.0.0.1:9864 9865 9866 /datanode.html
NodeManager:         http://127.0.0.1:8042 8043 8044 /node

Дополнительно поднят SOCKS5-прокси на 127.0.0.1:$SOCKS_PORT. Если в браузере
выбрать его и включить разрешение имён через прокси, интерфейсы открываются
по внутренним именам узлов (team-09-nn:9870 и т. д.), и переходы между
страницами работают без подмены адресов.

Прервать: Ctrl+C
TXT

exec ssh -N "${KEY_OPT[@]}" "${FORWARDS[@]}" -D "$SOCKS_PORT" "$EDGE_SSH"
