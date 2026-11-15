#!/usr/bin/env bash
# shot.sh — one-line screenshot of THIS worktree's game, isolated by instance identity.
#
# Replaces the pile of ad-hoc tools/*shot*.gd harnesses for the common case: "show me
# what MY game looks like right now". It starts the game for this worktree if none is
# already running (reuses it otherwise), captures through the peer pointing at this
# worktree's own player_id, downscales to a sane width, and writes the PNG where asked.
#
#   tools/shot.sh                                  # capture the current view
#   tools/shot.sh --out /tmp/a.png                 # pick the destination
#   tools/shot.sh --scene res://core_v2/levels/RingHub_Level.tscn
#   tools/shot.sh --scene <res://...> --pos "-6.2,-24.7,-0.4" --yaw 19.5
#   tools/shot.sh --headless                        # no window on the user's display
#   tools/shot.sh --width 1280                      # wider (hard-capped at 2000)
#   tools/shot.sh --no-launch                       # fail instead of starting a game
#
# Isolation: the game identity comes from this worktree (ODISEA_PLAYER_ID / --player-id),
# so a capture can only reach this worktree's game — never another agent's. If no game is
# connected for that id it launches one via tools/launch_game.sh (which also isolates
# user://); otherwise it reuses the running one. Every peer call carries player_id, and
# the peer refuses to guess when several games are connected (no silent cross-capture).
#
# Headless: with --headless the game runs `--no-window` so no window opens on :0. The
# capture reads the ROOT viewport, which still renders off-screen and includes the full
# frame: 3D plus the 2D layers (HUD, menus). ANNAV2 only falls back to a child Viewport
# when a game was started with ODISEA_SHOT_VIEWPORT=child (3D only, no 2D layers) — rarely
# needed. The log line reports which viewport was used.
#
# Default output: the session artifacts dir ($HOME/.ao/data/artifacts/$AO_SESSION_ID) when
# it exists, otherwise /tmp. Downscaled to at most --width px (default 800, max 2000); an
# image narrower than that is left untouched (never upscaled).
#
# Env: PEER_PORT (default 4999), ANNA_V2_BRIDGE (host:port) to select the peer; tooling
# resolves the fork binary via tools/godot_bin.sh (see tools/launch_game.sh).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PEER_PORT:-4999}"
PEER_URL="http://127.0.0.1:${PORT}"

SCENE=""
POS=""
YAW=""
HEADLESS=0
NO_LAUNCH=0
OUT=""
WIDTH=800
INSTANCE=""
PLAYER_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --scene) SCENE="$2"; shift 2 ;;
    --pos) POS="$2"; shift 2 ;;
    --yaw) YAW="$2"; shift 2 ;;
    --headless) HEADLESS=1; shift ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --width) WIDTH="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --player-id) PLAYER_ID="$2"; shift 2 ;;
    -h|--help) sed -n '2,36p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "shot.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Identity: same derivation launch_game.sh uses, so both agree on this worktree's game.
INSTANCE="${INSTANCE:-${ODISEA_INSTANCE:-$(basename "$REPO_ROOT")}}"
INSTANCE="$(printf '%s' "$INSTANCE" | tr -c 'A-Za-z0-9._-' '-')"
[ -n "$INSTANCE" ] || INSTANCE="odisea"
PLAYER_ID="${PLAYER_ID:-${ODISEA_PLAYER_ID:-$INSTANCE}}"

# Resize target: default 800, never above 2000 (downscale only).
if ! printf '%s' "$WIDTH" | grep -Eq '^[0-9]+$'; then
  echo "shot.sh: --width must be an integer" >&2; exit 2
fi
[ "$WIDTH" -gt 2000 ] && WIDTH=2000

cd "$REPO_ROOT"
bash tools/ensure_peer.sh --quiet || true

log() { echo "[shot] $*"; }

heartbeat() {
  curl -s --max-time 4 "${PEER_URL}/status?player_id=${PLAYER_ID}" 2>/dev/null || true
}

is_connected() {
  heartbeat | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
print("yes" if isinstance(d, dict) and d.get("player_id") == sys.argv[1] else "no")' "$PLAYER_ID" 2>/dev/null | grep -q yes
}

# A heartbeat survives on the peer for HEARTBEAT_TTL (~30s) after a game dies, so presence
# alone would reuse a corpse. Probe the live runtime instead (cheap, always player_id-scoped).
game_is_live() {
  is_connected || return 1
  curl -s --max-time 8 -XPOST "${PEER_URL}/command" -H "Content-Type: application/json" \
    -d "{\"action\":\"inspect_node\",\"player_id\":\"${PLAYER_ID}\",\"args\":{\"path\":\"/root\"}}" \
    | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
print("yes" if isinstance(d, dict) and d.get("ok") is True else "no")' 2>/dev/null | grep -q yes
}

drive_running_game() {
  # Drive an already-running game to the requested scene/pose, over the peer, always with
  # our player_id. Mirrors launch_game.sh's post-boot driving.
  if [ -n "$SCENE" ]; then
    log "goto_scene ${SCENE}"
    curl -s --max-time 10 "${PEER_URL}/eval" \
      --data-urlencode "expr=get_node('/root/SceneManager').goto_scene('${SCENE}')" \
      --data-urlencode "player_id=${PLAYER_ID}" -G >/dev/null || true
    local want cur
    want="$(basename "$SCENE" | sed 's/\.[^.]*$//')"
    for _ in $(seq 1 20); do
      cur="$(heartbeat | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
print(d.get("player", {}).get("scene", "") if isinstance(d, dict) else "")' 2>/dev/null || true)"
      [ "$cur" = "$want" ] && break
      sleep 1
    done
  fi
  if [ -n "$POS" ]; then
    IFS=',' read -r X Y Z <<< "$POS"
    local args="{\"position\":[${X},${Y},${Z}]"
    [ -n "$YAW" ] && args="${args},\"yaw\":${YAW}"
    args="${args}}"
    log "teleport_player ${args}"
    curl -s --max-time 10 -XPOST "${PEER_URL}/command" -H "Content-Type: application/json" \
      -d "{\"action\":\"teleport_player\",\"player_id\":\"${PLAYER_ID}\",\"args\":${args}}" >/dev/null || true
  fi
}

if game_is_live; then
  log "reusing running game: player_id=${PLAYER_ID} (instance=${INSTANCE})"
  drive_running_game
else
  if [ "$NO_LAUNCH" = "1" ]; then
    echo "shot.sh: no game connected for player_id=${PLAYER_ID} (worktree instance '${INSTANCE}') and --no-launch was set." >&2
    echo "shot.sh: start one with: tools/launch_game.sh --instance ${INSTANCE}" >&2
    exit 3
  fi
  log "no game for player_id=${PLAYER_ID}; launching this worktree's game"
  launch_args=(--instance "$INSTANCE")
  [ "$HEADLESS" = "1" ] && launch_args+=(--headless)
  [ -n "$SCENE" ] && launch_args+=(--scene "$SCENE")
  [ -n "$POS" ] && launch_args+=(--pos "$POS")
  [ -n "$YAW" ] && launch_args+=(--yaw "$YAW")
  # Propagate the chosen id to the launcher: with an explicit --player-id the game must
  # come up as that id, not as the instance-derived one, or the capture below cannot reach it.
  ODISEA_PLAYER_ID="$PLAYER_ID" bash tools/launch_game.sh "${launch_args[@]}"
fi

# Capture through the peer, always naming our player_id. "auto" lets the game pick the
# viewport: the root one by default (full frame incl. 2D HUD/menus); a child Viewport only
# if the game was started with ODISEA_SHOT_VIEWPORT=child. max_width downscales in-game,
# which is both what we want (<=800 px) and keeps the WebSocket frame small.
#
# Retry transient failures: a ~600 KB screenshot frame occasionally trips a Godot WS /
# aiohttp framing drop ("non-zero reserved bits"), which surfaces as one command timeout
# before the game reconnects. A retry a second later succeeds; permanent errors (missing
# player, bad request) are not retried.
capture_once() {
  RESP="$(curl -s --max-time 40 -XPOST "${PEER_URL}/command" -H "Content-Type: application/json" \
    -d "{\"action\":\"screenshot\",\"player_id\":\"${PLAYER_ID}\",\"args\":{\"viewport\":\"auto\",\"max_width\":${WIDTH}}}")"
  read -r SHOT_PATH RESP_VIEWPORT RESP_OK RESP_ERR < <(printf '%s' "$RESP" | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
if not isinstance(d, dict): d = {}
print(d.get("screenshot_path", ""), d.get("viewport", ""),
      "1" if d.get("ok") else "0", d.get("error", ""))' 2>/dev/null || true)
}

SHOT_PATH=""; RESP_VIEWPORT=""; RESP_OK=""; RESP_ERR=""
for attempt in 1 2 3; do
  capture_once
  [ -n "$SHOT_PATH" ] && [ -f "$SHOT_PATH" ] && break
  case "$RESP_ERR" in
    timeout|command_failed|no_game_connected)
      [ "$attempt" -lt 3 ] && { log "capture attempt ${attempt} failed (${RESP_ERR}); retrying"; sleep 1.5; continue; } ;;
  esac
  break
done

if [ "$RESP_OK" != "1" ] || [ -z "$SHOT_PATH" ] || [ ! -f "$SHOT_PATH" ]; then
  echo "shot.sh: capture failed for player_id=${PLAYER_ID} after retries." >&2
  echo "shot.sh: peer response: ${RESP}" >&2
  exit 4
fi

if [ -z "$RESP_VIEWPORT" ]; then
  echo "shot.sh: warning: the game returned no capture viewport field; it may predate the" >&2
  echo "shot.sh: windowless-capture support. If the image is black, relaunch it:" >&2
  echo "shot.sh:   tools/launch_game.sh --stop && tools/shot.sh --headless" >&2
fi

# Destination: explicit --out, else the session artifacts dir, else /tmp.
if [ -z "$OUT" ]; then
  AO_ARTIFACTS_ROOT="${AO_ARTIFACTS_DIR:-$HOME/.ao/data/artifacts}"
  if [ -n "${AO_SESSION_ID:-}" ] && [ -d "$AO_ARTIFACTS_ROOT/$AO_SESSION_ID" ]; then
    OUT="$AO_ARTIFACTS_ROOT/$AO_SESSION_ID/shot-${INSTANCE}-$(date +%Y%m%d-%H%M%S)-$$.png"
  else
    OUT="/tmp/shot-${INSTANCE}-$(date +%Y%m%d-%H%M%S)-$$.png"
  fi
fi
mkdir -p "$(dirname "$OUT")"

resize_to() {  # $1 src  $2 dst  $3 max width
  if python3 -c 'import PIL' 2>/dev/null; then
    python3 - "$1" "$2" "$3" <<'PY'
import sys
from PIL import Image
src, dst, maxw = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGBA")
w, h = im.size
if w > maxw:
    im = im.resize((maxw, max(1, round(h * maxw / w))), Image.LANCZOS)
im.save(dst)
print("%dx%d" % im.size)
PY
  elif command -v magick >/dev/null 2>&1; then
    magick "$1" -resize "${3}x>" "$2" && python3 -c "print('resized')"
  elif command -v convert >/dev/null 2>&1; then
    convert "$1" -resize "${3}x>" "$2" && python3 -c "print('resized')"
  else
    cp "$1" "$2"; echo "copied"
  fi
}

SIZE="$(resize_to "$SHOT_PATH" "$OUT" "$WIDTH")"
log "saved ${OUT} (${SIZE}, viewport=${RESP_VIEWPORT:-root}, player_id=${PLAYER_ID})"
echo "$OUT"
