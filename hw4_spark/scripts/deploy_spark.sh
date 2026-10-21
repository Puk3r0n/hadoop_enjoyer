#!/usr/bin/env bash
set -euo pipefail
D="$(dirname "$0")"
"$D/01_install_spark.sh"
"$D/02_configure_spark.sh"
"$D/03_run_job.sh"
"$D/04_verify_spark.sh"
