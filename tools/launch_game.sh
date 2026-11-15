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
# Identity and isolation (one game per worktree, no cross-talk):
#   Every worktree shares user:// (all copies of project.godot are config/name="Odisea"),
#   so two agents' games would report the same player_id and clobber each other on the
#   peer, which routes heartbeats and commands by player_id. This launcher fixes both:
#   - ODISEA_PLAYER_ID/ODISEA_INSTANCE is exported per worktree (default: the directory
#     name, e.g. src-53), so each game has its own identity.
#   - override.cfg points user:// at a per-instance dir (<data>/odisea-agents/<instance>),
#     so saves/settings/logs never cross between agents or with the human's editor game.
#   --instance <name> overrides the derived instance; ODISEA_PLAYER_ID wins over it.
#
# --lowend reproduces the low-end handheld on desktop: installs portmaster/lowend.cfg
# as override.cfg (stripping the .mobile suffixes so the flat keys apply without the
# "mobile" feature tag) and exports ODISEA_FORCE_LOW_TIER=1 for the runtime tier. The
# generated override.cfg is removed when this script exits (the engine only reads it at
# boot), and any pre-existing override.cfg is restored.
#
# Prints the connected instance, player_id and user:// dir on success. The game keeps
# running in the background (detached) so follow-up curl/MCP calls work; stop it with
# --stop.
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
INSTANCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --scene) SCENE="$2"; shift 2 ;;
    --pos) POS="$2"; shift 2 ;;
    --yaw) YAW="$2"; shift 2 ;;
    --headless) HEADLESS=1; shift ;;
    --lowend) LOWEND=1; shift ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --stop) DO_STOP=1; shift ;;
    -h|--help) sed -n '2,37p' "${BASH_SOURCE[0]}"; exit 0 ;;
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

# 0. Identity + user:// isolation (see header). One instance per worktree so two agents'
# games never share a player_id (the peer routes by it) or user:// (saves/settings/logs).
REPO_BASENAME="$(basename "$REPO_ROOT")"
INSTANCE="${INSTANCE:-${ODISEA_INSTANCE:-$REPO_BASENAME}}"
# Sanitize: safe for both the exported id and the custom user-dir name.
INSTANCE="$(printf '%s' "$INSTANCE" | tr -c 'A-Za-z0-9._-' '-')"
[ -n "$INSTANCE" ] || INSTANCE="odisea"
export ODISEA_INSTANCE="$INSTANCE"
export ODISEA_PLAYER_ID="${ODISEA_PLAYER_ID:-$INSTANCE}"
# A fresh isolated user:// has no saved telemetry consent, and ANNAV2 only connects to the
# peer when telemetry is on. This launcher exists to drive the game through the peer, so it
# opts in explicitly (a normal editor launch never does).
export ODISEA_FORCE_TELEMETRY=1
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
USER_DIR="$DATA_DIR/odisea-agents/$INSTANCE"

# 1. Peer must be up first so the game's discovery finds it immediately.
bash tools/ensure_peer.sh --quiet || true

# 1b. override.cfg: point user:// at a per-instance dir, and with --lowend install
# portmaster/lowend.cfg so the desktop boots with the RK3326 handheld render settings.
# On the device the launcher copies lowend.cfg as-is because FRT exposes the "mobile"
# feature tag; on desktop that tag is absent, so the .mobile suffixes are stripped to
# flat keys. The engine reads override.cfg only at boot, so it is removed when this
# script exits (the game is already running); a pre-existing file is restored.
OVERRIDE_CFG="$REPO_ROOT/override.cfg"
OVERRIDE_BACKUP="$OVERRIDE_CFG.lowend-backup"
if [ -f "$OVERRIDE_CFG" ]; then
  cp "$OVERRIDE_CFG" "$OVERRIDE_BACKUP"
fi
{
  echo '[application]'
  echo 'config/use_custom_user_dir=true'
  printf 'config/custom_user_dir_name="odisea-agents/%s"\n' "$INSTANCE"
  if [ "$LOWEND" = "1" ]; then
    echo
    sed -E 's/^([A-Za-z0-9_/]+)\.mobile=/\1=/' portmaster/lowend.cfg
  fi
} > "$OVERRIDE_CFG"
if [ "$LOWEND" = "1" ]; then
  export ODISEA_FORCE_LOW_TIER=1
  echo "[launch_game] low end: override.cfg from portmaster/lowend.cfg + ODISEA_FORCE_LOW_TIER=1"
fi
echo "[launch_game] instance=${INSTANCE} player_id=${ODISEA_PLAYER_ID}"
echo "[launch_game] user://=${USER_DIR}"
cleanup_override() {
  rm -f "$OVERRIDE_CFG"
  if [ -f "$OVERRIDE_BACKUP" ]; then
    mv "$OVERRIDE_BACKUP" "$OVERRIDE_CFG"
  fi
}
trap cleanup_override EXIT

players_now() { curl -s --max-time 3 "${PEER_URL}/status" 2>/dev/null; }

# 2. Launch the game detached. Debug build (no --release/--export) keeps commands enabled.
WINDOW_FLAGS=""
if [ "$HEADLESS" = "1" ]; then
  WINDOW_FLAGS="--no-window"
  # The root viewport reads black with --no-window, so ANNAV2 captures through a child
  # Viewport instead. tools/shot.sh relies on this for windowless screenshots.
  export ODISEA_SHOT_VIEWPORT=child
fi
echo "[launch_game] launching ${GODOT_BIN} ${WINDOW_FLAGS} (log: ${GAME_LOG})"
# shellcheck disable=SC2086
nohup "$GODOT_BIN" --path "$REPO_ROOT" $WINDOW_FLAGS >>"$GAME_LOG" 2>&1 &
GAME_PID=$!
echo "[launch_game] game pid ${GAME_PID}"

# 3. Wait for the peer to receive OUR heartbeat (this worktree's game booted). Matching by
# player_id is what keeps two agents' launches from cross-wiring: we must never adopt the
# first game that happens to be on the peer. A stale heartbeat from a previous run within
# the peer's TTL is skipped by requiring a new session_id.
WANT_PID="$ODISEA_PLAYER_ID"
heartbeat_field() {  # $1 = json field of our player's heartbeat
  curl -s --max-time 3 "${PEER_URL}/status?player_id=${WANT_PID}" 2>/dev/null | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
print(d.get(sys.argv[1], "") if isinstance(d, dict) else "")' "$1" 2>/dev/null || true
}
PRE_SESSION="$(heartbeat_field session_id)"
PLAYER_ID=""
for _ in $(seq 1 "$((READY_WAIT_SECS * 2))"); do
  if ! kill -0 "$GAME_PID" 2>/dev/null; then
    echo "[launch_game] game exited early. Last log:" >&2; tail -n 25 "$GAME_LOG" >&2; exit 1
  fi
  CUR_SESSION="$(heartbeat_field session_id)"
  if [ -n "$CUR_SESSION" ] && [ "$CUR_SESSION" != "$PRE_SESSION" ]; then
    PLAYER_ID="$WANT_PID"
    break
  fi
  sleep 0.5
done

if [ -z "$PLAYER_ID" ]; then
  echo "[launch_game] timed out waiting for a game with player_id=${WANT_PID} on the peer." >&2
  echo "[launch_game] if another game already holds that id, give this one --instance <name>." >&2
  tail -n 25 "$GAME_LOG" >&2; exit 1
fi
echo "[launch_game] connected: player_id=${PLAYER_ID}"

# 4. Optionally drive to a scene, then position the player. Every peer call carries
# player_id so commands can never land on another worktree's game.
if [ -n "$SCENE" ]; then
  echo "[launch_game] goto_scene ${SCENE}"
  curl -s --max-time 10 "${PEER_URL}/eval" \
    --data-urlencode "expr=get_node('/root/SceneManager').goto_scene('${SCENE}')" \
    --data-urlencode "player_id=${PLAYER_ID}" \
    -G >/dev/null || echo "[launch_game] warn: goto_scene eval failed (build may lack debug commands)" >&2
  # Poll telemetry until the target scene is actually live (boot/menu -> target can take
  # a few seconds), so a follow-up teleport lands on the right scene's player.
  WANT_SCENE="$(basename "$SCENE" | sed 's/\.[^.]*$//')"
  for _ in $(seq 1 20); do
    CUR="$(curl -s --max-time 3 "${PEER_URL}/status?player_id=${PLAYER_ID}" 2>/dev/null | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
print(d.get("player", {}).get("scene", "") if isinstance(d, dict) else "")' 2>/dev/null || true)"
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
