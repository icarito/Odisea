#!/usr/bin/env bash
set -euo pipefail

REPLAY_PATH="./replays/2025-12-23T22-33-15.json"
LOG_DIR="./tests/logs"
LOG_FILE="$LOG_DIR/replay_regression.log"

mkdir -p "$LOG_DIR"

echo "Running replay regression for: $REPLAY_PATH"
# Run the project's replay helper and capture all output
./replay.sh play --file "$REPLAY_PATH" 2>&1 | tee "$LOG_FILE"

# Search for known failure patterns
if grep -q -E "DETERMINISM TEST FAILED|\[REPLAY_ERROR\]|Invalid call\. Nonexistent function 'get_player'|SCRIPT ERROR" "$LOG_FILE"; then
  echo "Replay regression: FAIL — errores detectados. Ver $LOG_FILE"
  exit 1
fi

echo "Replay regression: PASS — no se detectaron errores en $LOG_FILE"
exit 0
