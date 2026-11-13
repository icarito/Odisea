#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-/tmp/rl12_fast_monitor.log}"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "log not found yet: $LOG_FILE"
  echo "start training first, then run:"
  echo "  $0 $LOG_FILE"
  exit 1
fi

echo "watching: $LOG_FILE"
echo "filters: monitor|stage=|eval_60hz|fps|entropy_loss|explained_variance|approx_kl|value_loss|saved="
tail -n 200 -f "$LOG_FILE" | rg --line-buffered "monitor|stage=|eval_60hz|fps|entropy_loss|explained_variance|approx_kl|value_loss|saved="
