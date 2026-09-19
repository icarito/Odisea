#!/usr/bin/env bash
# launch_game.sh — launch Odisea and (optionally) drive it to a scene/state, autonomously.
#
# Lets an agent boot its own game instead of depending on a human keeping one open. The
# game runs as a normal debug build (so OS.is_debug_build() is true and runtime commands like
# set_property/execute_script/teleport are allowed), with ANNAV2 telemetry on, and connects
# to the local peer. After the peer sees the first heartbeat we optionally change scene and
# place the player — all over the same peer command path the rest of the tooling uses.
#
#   tools/launch_game.sh                                  # headful, boot normally
#   tools/launch_game.sh --scene res://core_v2/levels/interiors/Dome_Crio.tscn
#   tools/launch_game.sh --scene <res://...> --pos "-6.2,-24.7,-0.4" --yaw 19.5
#   tools/launch_game.sh --headless                       # no window (autonomous checks)
#   tools/launch_game.sh --lowend                         # boot with the handheld tier LOW config
#   tools/launch_game.sh --scene <...> --quit-after 0     # leave it running, just print status
#
# --lowend reproduces the low-end handheld on desktop: installs portmaster/lowend.cfg
# as override.cfg (stripping the .mobile suffixes so the flat keys apply without the
# "mobile" feature tag) and exports ODISEA_FORCE_LOW_TIER=1 for the runtime tier. The
# generated override.cfg is removed when this script exits (the engine only reads it at
# boot), and any pre-existing override.cfg is restored.
#
# Prints the connected player_id and final /status on success. The game keeps running in the
# background (detached) so follow-up curl/MCP calls work; stop it with --stop.
#
# Env: GODOT_BIN (default: the fork resolved by tools/godot_bin.sh), PEER_PORT (default 4999).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El default es el editor del fork (tools/godot_bin.sh), NO `godot3-bin`: ese wrapper
# apunta a Godot 3.6.2 upstream, que no conoce Box3D ni las settings propias y pisa
# project.godot al salir (AGENTS.md §2.2).
GODOT_BIN="${GODOT_BIN:-$(sh "$(dirname "${BASH_SOURCE[0]}")/godot_bin.sh")}"
PORT="${PEER_PORT:-4999}"
PEER_URL="http://127.0.0.1:${PORT}"
GAME_LOG="${GAME_LOG:-/tmp/odisea_game.log}"
READY_WAIT_SECS="${READY_WAIT_SECS:-40}"

SCENE=""
POS=""
YAW=""
HEADLESS=0
DO_STOP=0
LOWEND=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scene) SCENE="$2"; shift 2 ;;
    --pos) POS="$2"; shift 2 ;;
    --yaw) YAW="$2"; shift 2 ;;
    --headless) HEADLESS=1; shift ;;
    --lowend) LOWEND=1; shift ;;
    --stop) DO_STOP=1; shift ;;
    -h|--help) sed -n '2,33p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$DO_STOP" = "1" ]; then
  # Solo el juego lanzado con --path, nunca el editor abierto del mismo binario.
  pkill -f "${GODOT_BIN} --path ${REPO_ROOT}" 2>/dev/null || true
  echo "[launch_game] stopped any running game for ${REPO_ROOT}"
  exit 0
fi

cd "$REPO_ROOT"

# 1. Peer must be up first so the game's discovery finds it immediately.
bash tools/ensure_peer.sh --quiet || true

# 1b. --lowend: install portmaster/lowend.cfg as the project override.cfg so the
# desktop boots with the same render settings as the RK3326 handhelds. On the
# device the launcher copies the file as-is because FRT exposes the "mobile"
# feature tag; on desktop that tag is absent, so the .mobile suffixes are stripped
# to flat keys. The engine reads override.cfg only at boot, so it is removed when
# this script exits (the game is already running).
OVERRIDE_CFG="$REPO_ROOT/override.cfg"
if [ "$LOWEND" = "1" ]; then
  export ODISEA_FORCE_LOW_TIER=1
  if [ -f "$OVERRIDE_CFG" ]; then
    cp "$OVERRIDE_CFG" "$OVERRIDE_CFG.lowend-backup"
  fi
  sed -E 's/^([A-Za-z0-9_/]+)\.mobile=/\1=/' portmaster/lowend.cfg > "$OVERRIDE_CFG"
  echo "[launch_game] low end: override.cfg from portmaster/lowend.cfg + ODISEA_FORCE_LOW_TIER=1"
fi
cleanup_override() {
  if [ "$LOWEND" = "1" ]; then
    rm -f "$OVERRIDE_CFG"
    if [ -f "$OVERRIDE_CFG.lowend-backup" ]; then
      mv "$OVERRIDE_CFG.lowend-backup" "$OVERRIDE_CFG"
    fi
  fi
}
trap cleanup_override EXIT

players_now() { curl -s --max-time 3 "${PEER_URL}/status" 2>/dev/null; }

# 2. Launch the game detached. Debug build (no --release/--export) keeps commands enabled.
WINDOW_FLAGS=""
[ "$HEADLESS" = "1" ] && WINDOW_FLAGS="--no-window"
echo "[launch_game] launching ${GODOT_BIN} ${WINDOW_FLAGS} (log: ${GAME_LOG})"
# shellcheck disable=SC2086
nohup "$GODOT_BIN" --path "$REPO_ROOT" $WINDOW_FLAGS >>"$GAME_LOG" 2>&1 &
GAME_PID=$!
echo "[launch_game] game pid ${GAME_PID}"

# 3. Wait for the peer to receive a heartbeat (the game booted and connected).
PLAYER_ID=""
for _ in $(seq 1 "$((READY_WAIT_SECS * 2))"); do
  if ! kill -0 "$GAME_PID" 2>/dev/null; then
    echo "[launch_game] game exited early. Last log:" >&2; tail -n 25 "$GAME_LOG" >&2; exit 1
  fi
  PLAYER_ID="$(players_now | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(next(iter(d)) if d else "")' 2>/dev/null || true)"
  [ -n "$PLAYER_ID" ] && break
  sleep 0.5
done

if [ -z "$PLAYER_ID" ]; then
  echo "[launch_game] timed out waiting for the game to connect to the peer." >&2
  tail -n 25 "$GAME_LOG" >&2; exit 1
fi
echo "[launch_game] connected: player_id=${PLAYER_ID}"

# 4. Optionally drive to a scene, then position the player.
if [ -n "$SCENE" ]; then
  echo "[launch_game] goto_scene ${SCENE}"
  curl -s --max-time 10 "${PEER_URL}/eval" \
    --data-urlencode "expr=get_node('/root/SceneManager').goto_scene('${SCENE}')" \
    -G >/dev/null || echo "[launch_game] warn: goto_scene eval failed (build may lack debug commands)" >&2
  # Poll telemetry until the target scene is actually live (boot/menu -> target can take
  # a few seconds), so a follow-up teleport lands on the right scene's player.
  WANT_SCENE="$(basename "$SCENE" | sed 's/\.[^.]*$//')"
  for _ in $(seq 1 20); do
    CUR="$(players_now | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(next(iter(d.values()),{}).get("player",{}).get("scene","")) if d else print("")' 2>/dev/null || true)"
    [ "$CUR" = "$WANT_SCENE" ] && break
    sleep 1
  done
fi

if [ -n "$POS" ]; then
  IFS=',' read -r X Y Z <<< "$POS"
  ARGS="{\"position\":[${X},${Y},${Z}]"
  [ -n "$YAW" ] && ARGS="${ARGS},\"yaw\":${YAW}"
  ARGS="${ARGS}}"
  echo "[launch_game] teleport_player ${ARGS}"
  curl -s --max-time 10 -XPOST "${PEER_URL}/command" -H "Content-Type: application/json" \
    -d "{\"action\":\"teleport_player\",\"player_id\":\"${PLAYER_ID}\",\"args\":${ARGS}}" >/dev/null || true
fi

echo "[launch_game] ready. Final status:"
curl -s --max-time 4 "${PEER_URL}/status?player_id=${PLAYER_ID}" | python3 -m json.tool 2>/dev/null || players_now
