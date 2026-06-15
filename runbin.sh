#!/bin/bash

# runbin.sh - Reproduce hotzone .bin captures locally with HotzonePlayer.
#
# Hotzone .bin files are binary performance captures (sustained low-FPS windows),
# not full input recordings. Format: 4-byte magic 0x485a4e32 ("HZN2") followed by
# a var2bytes() blob of a dict with keys: trigger, player_id, session_id,
# timestamp, scene, grid, frames. Each frame holds: input, dt, pos, fps, t.
#
# HotzonePlayer.tscn loads the captured scene, finds the player, restores the
# initial snapshot and replays the inputs frame by frame via player.step().
# In-player controls: Space pause/resume, Left/Right step, 1/2/4 speed, Esc quit.
#
# Usage:
#   ./runbin.sh --file <path.bin> [--scene <Name|res://...>] [--speed 1|2|4]
#   ./runbin.sh --list
#   ./runbin.sh --help

set -euo pipefail

GODOT_BIN="godot3-bin"
PROJECT_PATH="."
PLAYER_SCENE="core_v2/tools/HotzonePlayer.tscn"
# user://pending_hotzones/ resolves here for the "Odisea" project on Linux.
PENDING_DIR="${HOME}/.local/share/godot/app_userdata/Odisea/pending_hotzones"

# --- Colors ---
if [ -t 1 ]; then
    C_INFO=$'\033[0;36m'    # cyan
    C_OK=$'\033[0;32m'      # green
    C_WARN=$'\033[0;33m'    # yellow
    C_ERR=$'\033[0;31m'     # red
    C_DIM=$'\033[0;90m'     # gray
    C_RST=$'\033[0m'
else
    C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_RST=""
fi

info()  { echo "${C_INFO}[runbin]${C_RST} $*"; }
ok()    { echo "${C_OK}[runbin]${C_RST} $*"; }
warn()  { echo "${C_WARN}[runbin]${C_RST} $*" >&2; }
err()   { echo "${C_ERR}[runbin] ERROR:${C_RST} $*" >&2; }

usage() {
    cat <<EOF
${C_INFO}runbin.sh${C_RST} - reproduce hotzone .bin captures locally

${C_OK}Usage:${C_RST}
  $0 [<path.bin>] [--scene <Name>] [--speed 1|2|4] [--warmup <sec>]
  $0 --list
  $0 --help

${C_OK}Options:${C_RST}
  [<path.bin>]      Hotzone .bin to replay (HZN2 binary). May be given positionally
                    or via --file. If omitted, the most recent capture in the
                    pending dir is used.
  --file <path>     Same as the positional argument.
  --list            List .bin captures in the pending hotzones dir and exit.
  --scene <name>    Override the scene baked in the .bin. Accepts a known name
                    (Dome_Crio, OdiseaExterior, ScaffoldOrbit, TestScene_v2) or a
                    res:// path. Useful to test a hotzone in a different scene.
  --speed <1|2|4>   Initial playback speed (default 1). Changeable in-player with
                    keys 1/2/4.
  --warmup <sec>    Settle time before stepping inputs (default 1.5). The replay
                    loops automatically when it reaches the end.
  --help            Show this help.

${C_OK}In-player controls:${C_RST}
  Space        pause/resume          1/2/4  speed 1x/2x/4x
  Left/Right   step 1 frame          Esc    quit
  Ctrl+Arrow   step 10 frames        Ctrl+Shift+Arrow  step 30 frames
  (playback loops on finish; pausing also freezes the player animator)

${C_DIM}Pending dir: ${PENDING_DIR}${C_RST}
EOF
}

list_bins() {
    if [ ! -d "$PENDING_DIR" ]; then
        warn "Pending dir does not exist: $PENDING_DIR"
        return 1
    fi
    local found=0
    info "Hotzone captures in ${PENDING_DIR}:"
    while IFS= read -r -d '' f; do
        found=1
        local size
        size=$(du -h "$f" | cut -f1)
        printf '  %s%s%s  %s(%s)%s\n' "$C_OK" "$(basename "$f")" "$C_RST" "$C_DIM" "$size" "$C_RST"
    done < <(find "$PENDING_DIR" -maxdepth 1 -name '*.bin' -print0 2>/dev/null | sort -z)
    if [ "$found" -eq 0 ]; then
        warn "No .bin files found."
        return 1
    fi
}

latest_bin() {
    find "$PENDING_DIR" -maxdepth 1 -name '*.bin' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | cut -d' ' -f2-
}

# --- Parse args ---
FILE=""
SCENE=""
SPEED="1"
WARMUP="1.5"
DO_LIST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)   FILE="${2:-}"; shift 2 ;;
        --scene)  SCENE="${2:-}"; shift 2 ;;
        --speed)  SPEED="${2:-}"; shift 2 ;;
        --warmup) WARMUP="${2:-}"; shift 2 ;;
        --list)   DO_LIST=1; shift ;;
        --help|-h) usage; exit 0 ;;
        -*) err "Unknown option: $1"; echo; usage; exit 1 ;;
        *) FILE="$1"; shift ;;  # positional .bin path
    esac
done

if [ "$DO_LIST" -eq 1 ]; then
    list_bins
    exit $?
fi

# --- Validate ---
# No file given: fall back to the most recent capture in the pending dir.
if [ -z "$FILE" ]; then
    FILE="$(latest_bin)"
    if [ -z "$FILE" ]; then
        err "No .bin given and no captures found in $PENDING_DIR"
        usage
        exit 1
    fi
    info "No file given, using latest capture: $(basename "$FILE")"
fi

# Allow a bare basename to resolve against the pending dir for convenience.
if [ ! -f "$FILE" ] && [ -f "$PENDING_DIR/$FILE" ]; then
    FILE="$PENDING_DIR/$FILE"
fi

if [ ! -f "$FILE" ]; then
    err "File not found: $FILE"
    exit 1
fi

if [[ "$FILE" != *.bin ]]; then
    err "Expected a .bin file, got: $FILE"
    exit 1
fi

case "$SPEED" in
    1|2|4) ;;
    *) err "--speed must be 1, 2 or 4 (got: $SPEED)"; exit 1 ;;
esac

if ! [[ "$WARMUP" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    err "--warmup must be a non-negative number of seconds (got: $WARMUP)"
    exit 1
fi

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    err "$GODOT_BIN not found in PATH."
    exit 1
fi

ABS_FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

# --- Launch ---
ARGS=(--path "$PROJECT_PATH" --scene "$PLAYER_SCENE" --replay-file "$ABS_FILE" --replay-speed "$SPEED" --replay-warmup "$WARMUP")
if [ -n "$SCENE" ]; then
    ARGS+=(--replay-scene "$SCENE")
    info "Scene override: $SCENE"
fi

info "Replaying: $ABS_FILE"
info "Speed: ${SPEED}x  Warmup: ${WARMUP}s  (loops on finish)"
ok "Launching HotzonePlayer..."

exec "$GODOT_BIN" "${ARGS[@]}"
