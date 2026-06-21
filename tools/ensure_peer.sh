#!/usr/bin/env bash
# ensure_peer.sh — idempotently ensure the FD-162 telemetry peer is alive on :4999.
#
# Safe to call repeatedly: if the peer already answers /health it is a no-op. Otherwise
# it launches odisea_peer.py detached, waits for it to come up, and returns.
#
# This is the single entry point both the odisea-debug skill and the V2 MCP server use so
# that "talk to the running game" never requires remembering to start the peer by hand.
#
#   tools/ensure_peer.sh            # ensure it's up (quiet on success)
#   tools/ensure_peer.sh --status   # just report, don't launch
#
# Exit 0 = peer is up. Exit 1 = could not bring it up.

set -euo pipefail

PORT="${PEER_PORT:-4999}"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${PEER_LOG:-/tmp/odisea_peer.log}"
WAIT_SECS="${PEER_WAIT_SECS:-15}"

peer_alive() {
  curl -s --max-time 2 "$HEALTH_URL" 2>/dev/null | grep -q '"ok": *true'
}

if peer_alive; then
  [ "${1:-}" = "--quiet" ] || echo "[ensure_peer] peer already up on :${PORT}"
  exit 0
fi

if [ "${1:-}" = "--status" ]; then
  echo "[ensure_peer] peer NOT running on :${PORT}"
  exit 1
fi

PYTHON="${PYTHON_BIN:-python3}"

# Launch detached so it survives this shell. nohup + & keeps it running across turns.
cd "$REPO_ROOT"
echo "[ensure_peer] starting odisea_peer.py on :${PORT} (log: ${LOG_FILE})"
nohup "$PYTHON" odisea_peer.py >>"$LOG_FILE" 2>&1 &
PEER_PID=$!

# Poll /health until it answers or we time out.
for _ in $(seq 1 "$((WAIT_SECS * 2))"); do
  if peer_alive; then
    echo "[ensure_peer] peer up (pid ${PEER_PID}) on :${PORT}"
    exit 0
  fi
  # If the process already died, surface the log tail and fail fast.
  if ! kill -0 "$PEER_PID" 2>/dev/null; then
    echo "[ensure_peer] peer process exited early. Last log lines:" >&2
    tail -n 20 "$LOG_FILE" >&2 || true
    exit 1
  fi
  sleep 0.5
done

echo "[ensure_peer] timed out waiting for :${PORT}. Last log lines:" >&2
tail -n 20 "$LOG_FILE" >&2 || true
exit 1
