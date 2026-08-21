#!/usr/bin/env bash
# Comprueba que todo artefacto retirado por prepare_split_stream_mesh_reimport
# fue reconstruido por el importador de Godot.
set -euo pipefail

BACKUP_BASE="${SPLIT_STREAM_BACKUP_BASE:-build/split-stream-reimport-backup}"
latest_manifest="$(find "${BACKUP_BASE}" -type f -name manifest.txt -print | sort | tail -n 1)"
if [[ -z "${latest_manifest}" ]]; then
  echo "[split_stream_reimport] ERROR: no encontre un manifest de reimportacion." >&2
  exit 1
fi

missing=0
while IFS= read -r artifact; do
  if [[ ! -s "${artifact}" ]]; then
    echo "[split_stream_reimport] falta o esta vacio: ${artifact}" >&2
    missing=1
  fi
done < "${latest_manifest}"
if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi
echo "[split_stream_reimport] PASS. $(wc -l < "${latest_manifest}" | tr -d '[:space:]') artefactos reconstruidos."
