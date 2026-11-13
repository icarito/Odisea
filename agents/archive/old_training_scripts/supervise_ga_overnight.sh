#!/usr/bin/env bash
set -euo pipefail

LOG_A="${1:-/tmp/anna_ga_rl4_didactic_long_a.log}"
LOG_B="${2:-/tmp/anna_ga_rl4_didactic_long_b.log}"
INTERVAL_SEC="${INTERVAL_SEC:-180}"

snapshot() {
  local f="$1"
  echo "--- $(basename "$f")"
  if [[ ! -f "$f" ]]; then
    echo "missing"
    return
  fi
  rg -n "Traceback|RuntimeError|transport error|Broken pipe|failed to become ready|OverflowError" "$f" | tail -n 3 || true
  rg -n "\\[ga\\] eval|round=[0-9]+ score|\\[gate\\]|unlocked stage|checkpoint=.*size=|summary:" "$f" | tail -n 6 || true
}

while true; do
  {
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    ps -eo pid,etime,pcpu,pmem,args \
      | rg -i "evolve_anna_ga.py.*anna_ga_rl4_didactic_long|auto_train_anna.py.*anna_ga_rl4_didactic_long|godot3-server --path . --disable-render-loop --quiet res://core_v2/tests/TestScene_RL" \
      | rg -v rg || true
    snapshot "$LOG_A"
    snapshot "$LOG_B"
    echo
  } 
  sleep "$INTERVAL_SEC"
done
