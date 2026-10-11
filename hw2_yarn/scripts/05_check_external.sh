#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${INVENTORY:-$REPO_ROOT/inventory.env}"

ui_label() { echo "$1" | cut -d: -f1; }
ui_eport() { echo "$1" | cut -d: -f4; }
ui_path()  { echo "$1" | cut -d: -f5; }

TARGET=${1:-$EDGE_PUBLIC_IP}
fail=0

echo "Проверка опубликованных интерфейсов с внешней машины: $TARGET"
echo

printf '%-26s %-34s %s\n' "Демон" "Адрес" "Ответ"
for e in "${UI_ENDPOINTS[@]}" "Список интерфейсов:-:-:$UI_INDEX_PORT:/"; do
  port=$(ui_eport "$e"); path=$(ui_path "$e")
  code=$(curl -s -o /dev/null -w '%{http_code}' -L -m 10 "http://$TARGET:$port$path" 2>/dev/null)
  printf '%-26s %-34s %s\n' "$(ui_label "$e")" "http://$TARGET:$port$path" "$code"
  [[ $code == 200 ]] || fail=1
done

echo
if [[ $fail -eq 0 ]]; then
  echo "OK: все интерфейсы доступны снаружи"
else
  echo "Часть интерфейсов недоступна снаружи."
  echo "Ответ 000 означает, что TCP-соединение не установилось: порт закрыт"
  echo "фаерволом площадки. Проверить, какие порты пропускаются:"
  printf '  nc -z -w 4 %s 22   # должен открыться\n' "$TARGET"
  printf '  nc -z -w 4 %s %s\n' "$TARGET" "$(ui_eport "${UI_ENDPOINTS[0]}")"
  echo "Пока порты не открыты, доступ к интерфейсам — через hw2_yarn/scripts/connect_ui.sh"
  exit 1
fi
