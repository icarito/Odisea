#!/usr/bin/env bash
# eval.sh — headless direct-invocation driver for Odisea (Godot 3.6).
#
# Runs a snippet of GDScript inside a real SceneTree with no window, so you can
# import-and-call internal project code (generators, rotators, parsers, …) and
# print results — the fastest way to exercise the layer most PRs here touch,
# without launching the full game or its bridge.
#
# Two modes:
#   1. Inline body:   ./eval.sh '<gdscript that runs in _init() and prints>'
#   2. Script file:   ./eval.sh -f path/to/script.gd     (must `extends SceneTree`)
#
# The inline body is wrapped in a SceneTree._init() and `quit()` is called for
# you. `load("res://...")` resolves against the project. Audio is muted.
#
# Examples:
#   ./eval.sh 'print(OS.has_feature("threads"))'
#   ./eval.sh 'var m=load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new();
#              m.apply_params({"grid_width":8,"grid_depth":12});
#              print("cells=", m.generate_grid_data(7).size())'
#   ./eval.sh -f /tmp/my_check.gd
#
# Notes:
#   - "ERROR: NO GRAB" and a one-frame "LAG SPIKE" line are harmless headless noise.
#   - Filter your own output with a tag, e.g. print("[x] ...") then grep '\[x\]'.
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot3-bin}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"  # repo root (src/)
export ODISEA_FORCE_MUTE_AUDIO=1

usage() { echo "usage: $0 '<gdscript body>'   |   $0 -f script.gd" >&2; exit 2; }

if [ "${1:-}" = "-f" ]; then
  [ -n "${2:-}" ] || usage
  [ -f "$2" ] || { echo "no such file: $2" >&2; exit 2; }
  # Godot resolves scripts via res://, so the file must live under the project dir.
  # Copy any external file in (and clean it up); use in-place if already inside.
  case "$(cd "$(dirname "$2")" && pwd)" in
    "$PROJECT_DIR"*) SCRIPT_PATH="$2"; CLEANUP="" ;;
    *) SCRIPT_PATH="$(mktemp "${PROJECT_DIR}/_eval_XXXXXX.gd")"; cp "$2" "$SCRIPT_PATH"; CLEANUP="$SCRIPT_PATH" ;;
  esac
else
  [ -n "${1:-}" ] || usage
  BODY="$1"
  # Indent the body so it sits inside _init().
  INDENTED="$(printf '%s\n' "$BODY" | sed 's/^/\t/')"
  TMP="$(mktemp "${PROJECT_DIR}/_eval_XXXXXX.gd")"
  {
    echo "extends SceneTree"
    echo "func _init():"
    printf '%s\n' "$INDENTED"
    echo -e "\tquit()"
  } > "$TMP"
  SCRIPT_PATH="$TMP"
  CLEANUP="$TMP"
fi

# Godot needs the script reachable as res://; keep it under the project dir.
REL="res://$(python3 -c "import os,sys; print(os.path.relpath('$SCRIPT_PATH','$PROJECT_DIR'))")"

trap '[ -n "$CLEANUP" ] && rm -f "$CLEANUP"' EXIT
cd "$PROJECT_DIR"
# Filter the known headless boot/teardown noise so only your prints (and real
# errors) remain. Use EVAL_RAW=1 to see everything.
if [ -n "${EVAL_RAW:-}" ]; then
  timeout "${EVAL_TIMEOUT:-90}" "$GODOT_BIN" --no-window -s "$REL" 2>&1
else
  timeout "${EVAL_TIMEOUT:-90}" "$GODOT_BIN" --no-window -s "$REL" 2>&1 | grep -viE \
    "NO GRAB|set_mouse_mode|LAG SPIKE|performance_log|Mesa|OpenGL ES|Godot Engine v|\
\[AudioManager\]|\[SessionManager\]|\[PerformanceMonitor\]|\[ANNAV2\]|\
instances leaked|still in use at exit|MemoryPool allocs|_first != nullptr|self_list|\
norm_to_oct|Octahedral compression|run with --verbose|^ *$"
fi
