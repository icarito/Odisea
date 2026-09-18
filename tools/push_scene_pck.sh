#!/usr/bin/env bash
# push_scene_pck.sh — empuja una escena ad hoc a un juego Odisea corriendo (FD-162/ANNAV2).
#
# Empaqueta la escena (y archivos extra opcionales) en un .pck, lo sube al dispositivo
# con un sidecar de sha256 (la via dev de ANNAV2 reload_pck), y le ordena al juego
# cargar el pack y cambiar a la escena. La escena queda disponible como res:// dentro
# del juego: sus dependencias ya presentes en el pack principal se resuelven solas.
#
#   tools/push_scene_pck.sh res://core_v2/levels/RingHub_Level.tscn --no-launch
#   tools/push_scene_pck.sh res://tmp_ladder/s1a.tscn res://tmp_ladder/mat_extra.tres --id ladder1
#
# Puesta a punto del dispositivo (idempotente; reinicia el equipo):
#   tools/push_scene_pck.sh --setup      # peer local + engine debug en el device + dev.sh + reboot
#   tools/push_scene_pck.sh --restore    # saca dev.sh y vuelve al arranque normal
#
# Requisitos:
#   - Juego en build DEBUG corriendo y conectado al peer local (localhost:4999).
#     `--setup` lo deja asi en el Anbernic/RG351V (instala el engine debug del release
#     del fork, escribe dev.sh con ANNA_V2_BRIDGE y reinicia).
#   - Solo cambiar de escena cuando el juego esta idle en una escena (no en carga).
#
# Variables: PORTMASTER_HOST (default root@angel.local), PORTMASTER_DIR
# (default /storage/roms/ports/odisea), ANNA_PEER_URL (default http://localhost:4999),
# ANNA_BRIDGE_IP (default: IP local del escritorio), BOX3D_RELEASE (default: .github/box3d_release).
set -euo pipefail

SCENE=""
EXTRA_FILES=()
ARTIFACT=""
NO_LAUNCH=0
SETUP=0
RESTORE=0
ARGS=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --id) ARTIFACT="$2"; shift 2 ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    --setup) SETUP=1; shift ;;
    --restore) RESTORE=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "ERROR: opcion desconocida: $1" >&2; exit 1 ;;
    *) if [ -z "$SCENE" ]; then SCENE="$1"; else EXTRA_FILES+=("$1"); fi; shift ;;
  esac
done

HOST="${PORTMASTER_HOST:-root@angel.local}"
DEVICE_DIR="${PORTMASTER_DIR:-/storage/roms/ports/odisea}"
PEER="${ANNA_PEER_URL:-http://localhost:4999}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USERROOT="$DEVICE_DIR/conf/godot/app_userdata/Odisea"
DEBUG_ENGINE_NAME="odisea.frt.debug.aarch64"

peer_games() {
  curl -s --max-time 5 "$PEER/health" 2>/dev/null \
    | python3 -c "import json,sys;print(json.load(sys.stdin).get('games_connected',0))" 2>/dev/null || echo 0
}

desktop_ip() {
  if [ -n "${ANNA_BRIDGE_IP:-}" ]; then echo "$ANNA_BRIDGE_IP"; return; fi
  ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1
}

wait_for_game() {
  local timeout="${1:-150}" i=0
  echo "[push_scene_pck] esperando heartbeat del juego (hasta ${timeout}s)..."
  while [ "$i" -lt "$timeout" ]; do
    [ "$(peer_games)" = "1" ] && { echo "[push_scene_pck] juego conectado al peer."; return 0; }
    sleep 5; i=$((i + 5))
  done
  echo "ERROR: el juego no aparecio en $PEER/health" >&2; return 1
}

restore_device() {
  echo "[push_scene_pck] restaurando arranque normal del port..."
  ssh "$HOST" "rm -f $DEVICE_DIR/dev.sh" || true
  ssh "$HOST" "sync; (sleep 1; reboot) >/dev/null 2>&1 &" || true
  echo "[push_scene_pck] reboot enviado; el port arranca sin dev.sh."
}

setup_device() {
  local ip
  ip="$(desktop_ip)"
  [ -n "$ip" ] || { echo "ERROR: no pude detectar la IP del escritorio; usa ANNA_BRIDGE_IP=..." >&2; exit 1; }
  echo "[push_scene_pck] setup del device via $HOST (bridge $ip:4999)"
  "$REPO_ROOT/tools/ensure_peer.sh" >/dev/null 2>&1 || true

  # Engine debug del release pinneado del fork (reload_pck/eval requieren build debug).
  if ! ssh "$HOST" "test -x $DEVICE_DIR/$DEBUG_ENGINE_NAME"; then
    local pin asset tmpdl
    pin="$(tr -d '[:space:]' < "$REPO_ROOT/.github/box3d_release")"
    asset="godot.box3d.frt.arm64.debug"
    tmpdl="$(mktemp)"
    echo "[push_scene_pck] bajando $asset ($pin) del fork..."
    curl -fsSL -o "$tmpdl" "https://github.com/icarito/godot-box3d-3/releases/download/$pin/$asset"
    scp -q "$tmpdl" "$HOST:$DEVICE_DIR/$DEBUG_ENGINE_NAME"
    ssh "$HOST" "chmod +x $DEVICE_DIR/$DEBUG_ENGINE_NAME"
    rm -f "$tmpdl"
  fi

  # dev.sh: engine debug + bridge al peer del escritorio.
  ssh "$HOST" "cat > $DEVICE_DIR/dev.sh <<'EOF'
# Hook de desarrollo (no viaja en el paquete): engine DEBUG para comandos ANNAV2
# (reload_pck, eval) + bridge al peer de escritorio.
export ENGINE=$DEVICE_DIR/$DEBUG_ENGINE_NAME
export ANNA_V2_BRIDGE=$ip:4999
export ODISEA_ALLOW_ANNA_REMOTE_DEBUG=1
EOF"

  if [ "$(peer_games)" = "1" ]; then
    echo "[push_scene_pck] ya hay un juego debug conectado; no reinicio."
  else
    ssh "$HOST" "sync; (sleep 1; reboot) >/dev/null 2>&1 &" || true
    wait_for_game 180
  fi
}

if [ "$RESTORE" -eq 1 ]; then
  restore_device
  exit 0
fi

if [ "$SETUP" -eq 1 ]; then
  setup_device
fi

if [ -z "$SCENE" ]; then
  [ "$SETUP" -eq 1 ] && exit 0
  echo "uso: push_scene_pck.sh <res://escena.tscn> [extra...] [--id <id>] [--no-launch] | --setup | --restore" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$SCENE" in
  res://*) ;;
  *) echo "ERROR: la escena debe ser una ruta res:// (ej: res://core_v2/tests/TestScene_base.tscn)" >&2; exit 1 ;;
esac
SCENE_RELPATH="${SCENE#res://}"
[ -f "$REPO_ROOT/$SCENE_RELPATH" ] || { echo "ERROR: no existe $REPO_ROOT/$SCENE_RELPATH" >&2; exit 1; }

ARTIFACT="${ARTIFACT:-$(basename "$SCENE_RELPATH" .tscn)_$(date +%s)}"

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
INJECT="{\"artifact_id\":\"$ARTIFACT\""
if [ "$NO_LAUNCH" -eq 0 ]; then
  INJECT="$INJECT,\"scene\":\"$SCENE\""
fi
INJECT="$INJECT}"
RESP=$(curl -s --max-time 60 -XPOST "$PEER/command" -H "Content-Type: application/json" \
  -d "{\"action\":\"reload_pck\",\"args\":$INJECT}")
echo "$RESP" | grep -q '"ok": *true' || { echo "ERROR: reload_pck fallo: $RESP" >&2; exit 1; }

echo "[push_scene_pck] $SCENE -> artifact $ARTIFACT ($SHA256) cargado en el juego"
if [ "$NO_LAUNCH" -eq 0 ]; then
  echo "[push_scene_pck] escena activa: $SCENE"
else
  echo "[push_scene_pck] para entrar con el flujo normal (spawn del Pilot):"
  echo "  curl -s --get --data-urlencode \"expr=get_node('/root/SceneManager').goto_scene('$SCENE')\" \$ANNA_PEER_URL/eval"
fi
