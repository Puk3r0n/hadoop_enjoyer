#!/usr/bin/env bash
set -euo pipefail
D="$(dirname "$0")"
"$D/01_prepare_nodes.sh"
"$D/02_install_hadoop.sh"
"$D/03_configure_hdfs.sh"
"$D/04_start_hdfs.sh"
"$D/05_verify_hdfs.sh"
