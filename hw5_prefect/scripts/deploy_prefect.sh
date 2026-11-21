#!/usr/bin/env bash
set -euo pipefail
D="$(dirname "$0")"
"$D/01_install_prefect.sh"
"$D/02_run_flow.sh"
"$D/03_verify.sh"
