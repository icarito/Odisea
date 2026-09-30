#!/usr/bin/env bash
# Corre la prueba de Slug (tools/slug_probe) en el Anbernic.
#
# Exporta el pck con el headless de nightly5, sube el binario FRT arm64 del
# mismo release y el pck a /storage/roms/ports/odisea/slug_probe/, y ejecuta la
# prueba por ssh en cada modo (slug / label3d / viewport) con el mismo entorno
# que usa Odisea.sh (XDG a conf/, LD_LIBRARY_PATH, --video-driver GLES3,
# --resolution 640x480 -f). Despues trae los json y las capturas a results/.
#
# Uso:
#   tools/slug_probe/run_on_anbernic.sh                 # los 3 modos
#   tools/slug_probe/run_on_anbernic.sh slug            # un modo
#   SLUG_PROBE_HOST=root@1.2.3.4 tools/slug_probe/run_on_anbernic.sh
#   tools/slug_probe/run_on_anbernic.sh --no-build      # reusa el pck existente
#
# Si el device no responde por ssh, avisa y sale con 2 sin tocar nada.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="${SLUG_PROBE_RELEASE:-v0.5.4-nightly5}"
CACHE="${ODISEA_GODOT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/odisea-godot}/$RELEASE"
HEADLESS="$CACHE/godot.box3d.linux.x86_64.headless"
FRT="$CACHE/godot.box3d.frt.arm64.release"
TEMPLATES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/templates/3.6.4.rc.custom_build"
PRESET="Linux/X11"

HOST="${SLUG_PROBE_HOST:-root@angel.local}"
DEVICE_DIR="${SLUG_PROBE_DIR:-/storage/roms/ports/odisea/slug_probe}"
CONFDIR="${SLUG_PROBE_CONF:-/storage/roms/ports/odisea/conf}"
USERDATA="$CONFDIR/godot/app_userdata/SlugProbe"
RESULT_DIR="$HERE/results"

SSH_OPTS=(-o ConnectTimeout=8 -o StrictHostKeyChecking=no)

build_pck=1
modes=()
for arg in "$@"; do
	case "$arg" in
		--no-build) build_pck=0 ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		-*) echo "opcion desconocida: $arg" >&2; exit 1 ;;
		*) modes+=("$arg") ;;
	esac
done
if [ "${#modes[@]}" -eq 0 ]; then
	modes=(slug label3d viewport)
fi

log() { printf '[slug_probe] %s\n' "$*" >&2; }

ensure_bin() {
	local name="$1" dest="$2"
	if [ -x "$dest" ]; then
		return 0
	fi
	mkdir -p "$CACHE"
	log "bajando $name ($RELEASE)..."
	gh release download "$RELEASE" -R icarito/godot-box3d-3 -p "$name" -O "$dest" --clobber
	chmod +x "$dest"
}

ensure_templates() {
	local tpl="$TEMPLATES_DIR/linux_x11_64_release"
	if [ -x "$tpl" ]; then
		return 0
	fi
	local tpz="$CACHE/Godot-Box3D-export-templates-3.6.4.rc.custom_build.tpz"
	if [ ! -f "$tpz" ]; then
		log "bajando export templates de $RELEASE..."
		mkdir -p "$CACHE"
		gh release download "$RELEASE" -R icarito/godot-box3d-3 \
			-p "Godot-Box3D-export-templates-3.6.4.rc.custom_build.tpz" -O "$tpz" --clobber
	fi
	log "instalando template linux_x11_64_release..."
	mkdir -p "$TEMPLATES_DIR"
	unzip -o -j "$tpz" "templates/linux_x11_64_release" -d "$TEMPLATES_DIR" >/dev/null
	chmod +x "$tpl"
}

device_reachable() {
	ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$HOST" true 2>/dev/null
}

remote_script() {
	local mode="$1"
	cat <<REMOTE
set -e
cd "$DEVICE_DIR"
export HOME=/storage
export XDG_RUNTIME_DIR=/var/run/0-runtime-dir
export WAYLAND_DISPLAY=wayland-1
export SDL_VIDEODRIVER=wayland
export MALI_DEFAULT_DISPLAY=wayland
export DISPLAY=:0.0
export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export LD_LIBRARY_PATH="/usr/lib:$DEVICE_DIR/lib:\${LD_LIBRARY_PATH:-}"
export SLUG_PROBE_MODE="$mode"
rm -f "$USERDATA/slug_probe.json" "$USERDATA/slug_probe_$mode.png" 2>/dev/null || true
timeout 180 ./godot.box3d.frt.arm64.release \\
	--video-driver GLES3 --resolution 640x480 -f \\
	--main-pack slug_probe.pck
echo "[remote] exit=\$?"
REMOTE
}

fetch_results() {
	local mode="$1"
	mkdir -p "$RESULT_DIR"
	scp "${SSH_OPTS[@]}" -q \
		"$HOST:$USERDATA/slug_probe.json" "$RESULT_DIR/slug_probe_$mode.json" 2>/dev/null || true
	scp "${SSH_OPTS[@]}" -q \
		"$HOST:$USERDATA/slug_probe_$mode.png" "$RESULT_DIR/slug_probe_$mode.png" 2>/dev/null || true
}

if ! device_reachable; then
	log "el device $HOST no responde por ssh; nada que hacer."
	log "cuando este en linea: $0 ${modes[*]}"
	exit 2
fi

ensure_bin "godot.box3d.linux.x86_64.headless" "$HEADLESS"
ensure_bin "godot.box3d.frt.arm64.release" "$FRT"

if [ "$build_pck" -eq 1 ]; then
	ensure_templates
	log "exportando pck..."
	mkdir -p "$HERE/build"
	"$HEADLESS" --path "$HERE" --export-pack "$PRESET" "$HERE/build/slug_probe.pck"
	log "pck listo: $HERE/build/slug_probe.pck"
fi

if [ ! -f "$HERE/build/slug_probe.pck" ]; then
	log "falta build/slug_probe.pck; corre sin --no-build."
	exit 1
fi

log "preparando $DEVICE_DIR en $HOST..."
ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p '$DEVICE_DIR'"
scp "${SSH_OPTS[@]}" -q "$FRT" "$HOST:$DEVICE_DIR/godot.box3d.frt.arm64.release"
scp "${SSH_OPTS[@]}" -q "$HERE/build/slug_probe.pck" "$HOST:$DEVICE_DIR/slug_probe.pck"
ssh "${SSH_OPTS[@]}" "$HOST" "chmod +x '$DEVICE_DIR/godot.box3d.frt.arm64.release'"

for mode in "${modes[@]}"; do
	log "corriendo modo=$mode..."
	remote_script "$mode" | ssh "${SSH_OPTS[@]}" "$HOST" "bash -s" 2>&1 | sed "s/^/[$mode] /"
	fetch_results "$mode"
	if [ -f "$RESULT_DIR/slug_probe_$mode.json" ]; then
		log "resultado $mode: $RESULT_DIR/slug_probe_$mode.json"
	else
		log "sin json para $mode (revisar el log de arriba)"
	fi
done

log "listo. resultados en $RESULT_DIR"
