#!/usr/bin/env bash
set -euo pipefail
D="$(dirname "$0")"
"$D/01_configure_yarn.sh"
"$D/02_start_yarn.sh"
"$D/03_publish_ui.sh"
"$D/04_verify_yarn.sh"
