#!/bin/bash
# scaffold_rev.sh — Dibuja los andamios de Dome_Intro tal como quedaron en un commit,
# para recorrer el historial y ver en cual el encastre spoke <-> rampa estaba bien.
#
# Extrae las mallas horneadas de ese commit a res://core_v2/levels/interiors/_rev/
# y las renderiza en planta con tools/shot_scaffold_rev.gd. No toca el working tree.
#
# Uso: tools/scaffold_rev.sh <commit> [<commit> ...]
#      SALIDA=/tmp/revs tools/scaffold_rev.sh daad3ab2 92d33b4d

set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT_BIN:-godot3-bin}"
OUT_DIR="${SALIDA:-/tmp/odisea_scaffold_revs}"
REV_DIR="core_v2/levels/interiors/_rev"
# Ojo: NO llamar a este array GROUPS. En bash GROUPS es una variable especial
# de solo lectura (los gids del usuario): asignarla se ignora en silencio y el
# bucle termina iterando sobre "1000".
SCAFFOLD_GROUPS=(SpiralStairs HubSpokes SpiralWalkways)

mkdir -p "$OUT_DIR"
trap 'rm -rf "$REV_DIR"' EXIT

for commit in "$@"; do
  rm -rf "$REV_DIR"; mkdir -p "$REV_DIR"
  for group in "${SCAFFOLD_GROUPS[@]}"; do
    git show "${commit}:core_v2/levels/interiors/DomeIntro_${group}_baked.mesh" \
      > "$REV_DIR/DomeIntro_${group}_baked.mesh" 2>/dev/null || true
    for s in 00 01 02 03 04 05 06 07; do
      git show "${commit}:core_v2/levels/interiors/DomeIntro_${group}_sector_${s}.mesh" \
        > "$REV_DIR/DomeIntro_${group}_sector_${s}.mesh" 2>/dev/null \
        || rm -f "$REV_DIR/DomeIntro_${group}_sector_${s}.mesh"
    done
  done
  find "$REV_DIR" -size 0 -delete
  subject=$(git log -1 --format='%h %ad %s' --date=short "$commit")
  ODISEA_REV_DIR="res://$REV_DIR" \
  ODISEA_REV_OUT="$OUT_DIR/$commit" \
  ODISEA_REV_LABEL="$subject" \
    "$GODOT" --no-window -s tools/shot_scaffold_rev.gd 2>&1 | grep '^REV:' || true
done
