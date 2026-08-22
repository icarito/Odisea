#!/usr/bin/env bash
# Godot 3 importa asincronicamente y no debe recibir --quit: se le da una
# ventana finita y su resultado real se determina despues por los artefactos
# reconstruidos, no por los warnings de assets legacy ajenos a split_stream.
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot3-bin}"
TIMEOUT_SEC="${SPLIT_STREAM_IMPORT_TIMEOUT_SEC:-180}"
LOG_PATH="${SPLIT_STREAM_IMPORT_LOG:-reports/split_stream_mesh_reimport.log}"
mkdir -p "$(dirname "${LOG_PATH}")"

set +e
timeout --signal=TERM --kill-after=15s "${TIMEOUT_SEC}s" \
  "${GODOT_BIN}" --path . -e --headless --no-window --audio-driver Dummy > "${LOG_PATH}" 2>&1
status=$?
set -e
tail -60 "${LOG_PATH}"
case "${status}" in
  0) echo "[split_stream_reimport] Godot termino el import." ;;
  124|137) echo "[split_stream_reimport] Ventana de ${TIMEOUT_SEC}s finalizada; se verificaran los artefactos." ;;
  *)
    echo "[split_stream_reimport] Godot termino con exit=${status}; se verificaran los artefactos." >&2
    ;;
esac
