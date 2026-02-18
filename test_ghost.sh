#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot3-bin}"
SCENE="${GHOST_SCENE:-res://core_v2/levels/TestSceneGhost.tscn}"
SCRIPT_PATH="${GHOST_OYS_SCRIPT:-./core_v2/scripts/test_ghost_smoke.oys}"

HEADLESS=0
if [[ "${1:-}" == "--headless" ]]; then
  HEADLESS=1
fi

echo "🎬 Running Ghost smoke script"
echo "Scene:  $SCENE"
echo "Script: $SCRIPT_PATH"
echo "Godot:  $GODOT_BIN"

if [[ $HEADLESS -eq 1 ]]; then
  "$GODOT_BIN" --path . --no-window "$SCENE" --run-script "$SCRIPT_PATH"
else
  "$GODOT_BIN" --path . "$SCENE" --run-script "$SCRIPT_PATH"
fi
