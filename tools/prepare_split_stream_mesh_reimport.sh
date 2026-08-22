#!/usr/bin/env bash
# Fuerza la reimportacion de las escenas de malla sin borrar sus sidecars
# *.import ni ningun artefacto que no derive de una malla fuente. Conserva una
# copia recuperable bajo build/ antes de que Godot reconstruya los destinos.
set -euo pipefail

BACKUP_BASE="${SPLIT_STREAM_BACKUP_BASE:-build/split-stream-reimport-backup}"
mkdir -p "${BACKUP_BASE}"
BACKUP_DIR="$(mktemp -d "${BACKUP_BASE}/run.XXXXXX")"
MANIFEST="${BACKUP_DIR}/manifest.txt"
mkdir -p "${BACKUP_DIR}"

move_artifact() {
  local artifact="$1"
  [[ -f "${artifact}" ]] || return 0
  local backup_path="${BACKUP_DIR}/${artifact}"
  mkdir -p "$(dirname "${backup_path}")"
  mv "${artifact}" "${backup_path}"
  printf '%s\n' "${artifact}" >> "${MANIFEST}"
}

while IFS= read -r -d '' sidecar; do
  source_file="$(sed -n 's/^source_file="res:\/\/\(.*\)"$/\1/p' "${sidecar}")"
  dest_file="$(sed -n 's/^path="res:\/\/\(\.import\/.*\)"$/\1/p' "${sidecar}")"
  if [[ -z "${source_file}" || -z "${dest_file}" || ! -f "${source_file}" ]]; then
    echo "[split_stream_reimport] sidecar invalido: ${sidecar}" >&2
    exit 1
  fi
  move_artifact "${dest_file}"
  move_artifact "${dest_file%.*}.md5"
done < <(git ls-files -z -- '*.glb.import' '*.gltf.import' '*.obj.import' '*.dae.import' '*.fbx.import')

count="$(wc -l < "${MANIFEST}" | tr -d '[:space:]')"
if [[ "${count}" == "0" ]]; then
  echo "[split_stream_reimport] No habia artefactos de malla para reimportar."
  exit 0
fi
echo "[split_stream_reimport] ${count} artefactos movidos a ${BACKUP_DIR}"
echo "[split_stream_reimport] Godot debe reconstruir los paths de ${MANIFEST}"
