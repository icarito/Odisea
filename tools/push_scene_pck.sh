#!/usr/bin/env bash
# push_scene_pck.sh — empuja una escena ad hoc a un juego Odisea corriendo (FD-162/ANNAV2).
#
# Empaqueta la escena (y archivos extra opcionales) en un .pck, lo sube al dispositivo
# con un sidecar de sha256 (la via dev de ANNAV2 reload_pck), y le ordena al juego
# cargar el pack y cambiar a la escena. La escena queda disponible como res:// dentro
# del juego: sus dependencias ya presentes en el pack principal se resuelven solas.
#
#   tools/push_scene_pck.sh res://core_v2/tests/TestScene_base.tscn
#   tools/push_scene_pck.sh res://tmp_ladder/s1a.tscn res://tmp_ladder/mat_extra.tres --id ladder1
#
# Requisitos:
#   - Juego en build DEBUG corriendo y conectado al peer local (localhost:4999).
#     En el Anbernic: dev.sh con el binario debug + tools/ensure_peer.sh.
#   - Solo cambiar de escena cuando el juego este idle en una escena (no en carga).
#
# Variables: PORTMASTER_HOST (default root@angel.local), PORTMASTER_DIR
# (default /storage/roms/ports/odisea), ANNA_PEER_URL (default http://localhost:4999).
set -euo pipefail

SCENE="${1:?uso: push_scene_pck.sh <res://escena.tscn> [extra_res_file...] [--id <artifact_id>] [--no-launch]}"
shift || true
EXTRA_FILES=()
ARTIFACT=""
NO_LAUNCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --id) ARTIFACT="$2"; shift 2 ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    *) EXTRA_FILES+=("$1"); shift ;;
  esac
done

HOST="${PORTMASTER_HOST:-root@angel.local}"
DEVICE_DIR="${PORTMASTER_DIR:-/storage/roms/ports/odisea}"
PEER="${ANNA_PEER_URL:-http://localhost:4999}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$SCENE" in
  res://*) ;;
  *) echo "ERROR: la escena debe ser una ruta res:// (ej: res://core_v2/tests/TestScene_base.tscn)" >&2; exit 1 ;;
esac
SCENE_RELPATH="${SCENE#res://}"
[ -f "$REPO_ROOT/$SCENE_RELPATH" ] || { echo "ERROR: no existe $REPO_ROOT/$SCENE_RELPATH" >&2; exit 1; }

ARTIFACT="${ARTIFACT:-$(basename "$SCENE_RELPATH" .tscn)_$(date +%s)}"
USERROOT="$DEVICE_DIR/conf/godot/app_userdata/Odisea"

# 1. Empaquetar con PCKPacker via el editor del fork (res:// resuelve al repo).
{
  echo 'extends SceneTree'
  echo 'func _init() -> void:'
  echo -e "\tvar p := PCKPacker.new()"
  echo -e "\tp.pck_start(\"$TMP/$ARTIFACT.pck\")"
  echo -e "\tp.add_file(\"res://$SCENE_RELPATH\", \"res://$SCENE_RELPATH\")"
  for f in "${EXTRA_FILES[@]:-}"; do
    [ -n "$f" ] || continue
    case "$f" in res://*) ;; *) echo "ERROR: los extras deben ser rutas res://: $f" >&2; exit 1 ;; esac
    echo -e "\tp.add_file(\"$f\", \"$f\")"
  done
  echo -e "\tp.flush()"
  echo -e "\tquit()"
} > "$TMP/make_pack.gd"

( cd "$REPO_ROOT" && tools/godot --headless -s "$TMP/make_pack.gd" 2>&1 | grep -vE "^$" | tail -2 )
[ -s "$TMP/$ARTIFACT.pck" ] || { echo "ERROR: el pack no se genero" >&2; exit 1; }

# 2. Subir pck + sidecar sha256 (la via dev de _cmd_reload_pck).
SHA256=$(sha256sum "$TMP/$ARTIFACT.pck" | cut -d' ' -f1)
ssh "$HOST" "mkdir -p $USERROOT/updates/packages"
scp -q "$TMP/$ARTIFACT.pck" "$HOST:$USERROOT/updates/packages/$ARTIFACT.pck"
ssh "$HOST" "printf '%s' '{\"sha256\": \"$SHA256\"}' > $USERROOT/updates/packages/$ARTIFACT.json"

# 3. Inyectar y (opcional) cambiar a la escena.
ARGS="{\"artifact_id\":\"$ARTIFACT\""
if [ "$NO_LAUNCH" -eq 0 ]; then
  ARGS="$ARGS,\"scene\":\"$SCENE\""
fi
ARGS="$ARGS}"
RESP=$(curl -s --max-time 60 -XPOST "$PEER/command" -H "Content-Type: application/json" \
  -d "{\"action\":\"reload_pck\",\"args\":$ARGS}")
echo "$RESP" | grep -q '"ok": *true' || { echo "ERROR: reload_pck fallo: $RESP" >&2; exit 1; }

echo "[push_scene_pck] $SCENE -> artifact $ARTIFACT ($SHA256) cargado en el juego"
[ "$NO_LAUNCH" -eq 0 ] && echo "[push_scene_pck] escena activa: $SCENE"
