#!/usr/bin/env bash
set -euo pipefail
D="$(dirname "$0")"
"$D/01_install_postgres.sh"
"$D/02_install_hive.sh"
"$D/03_configure_hive.sh"
"$D/04_start_hive.sh"
"$D/05_load_data.sh"
"$D/06_verify_hive.sh"
