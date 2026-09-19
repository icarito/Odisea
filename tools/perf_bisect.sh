#!/usr/bin/env bash
# perf_bisect.sh — barre variantes de entorno sobre el bench de replay determinista
# en el device (RG351V), midiendo ticks/s y el desglose del profiler del fork (FRT_PERF).
#
#   PORTMASTER_HOST=root@192.168.18.36 tools/perf_bisect.sh \
#     "ODISEA_PHYSICS_FPS=30" \
#     "ODISEA_PHYSICS_FPS=20" \
#     "ODISEA_PHYSICS_FPS=20 ODISEA_UNSHADED=2"
#
# Cada variante: escribe el dev.sh del port, reinicia, corre el replay con FRT_PERF=1,
# mide la ventana de ticks fija (PERF_TICK0..PERF_TICK1) y printea una fila.
# Requiere: engine del device con el patch del profiler, replay en el user:// del port,
# peer local (tools/ensure_peer.sh) y el binario debug/release con --replay soportado.
set -u

HOST="${PORTMASTER_HOST:-root@angel.local}"
DIR="${PORTMASTER_DIR:-/storage/roms/ports/odisea}"
PEER="${ANNA_PEER_URL:-http://localhost:4999}"
T0="${PERF_TICK0:-100}"
T1="${PERF_TICK1:-400}"
REPLAY="${ODISEA_PERF_REPLAY:-$DIR/conf/godot/app_userdata/Odisea/replay_1789738542.json}"

if [ "$#" -eq 0 ]; then
	echo "uso: perf_bisect.sh \"ENV=val ...\" [\"ENV=val ...\" ...]" >&2
	exit 1
fi

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ensure_peer.sh" >/dev/null 2>&1 || true
IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)

wait_game() {
	local i=0
	while [ "$i" -lt 150 ]; do
		local n
		n=$(curl -s --max-time 5 "$PEER/health" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('games_connected',0))" 2>/dev/null || echo 0)
		[ "$n" = "1" ] && return 0
		sleep 5; i=$((i + 5))
	done
	return 1
}

measure() {
	python3 - "$PEER" "$T0" "$T1" <<'PY'
import json, time, urllib.request, sys, statistics
peer, t0, t1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def st():
    try:
        d = json.load(urllib.request.urlopen(peer + "/status", timeout=5))
        for v in d.values():
            if isinstance(v, dict): return v.get("player") or {}
    except Exception: pass
    return {}
start = time.time(); p = {}
while time.time() - start < 240:
    p = st()
    if (p.get("tick") or 0) >= t0: break
    time.sleep(1)
ts = ks = None; fps = []; dc = []
while time.time() - start < 700:
    p = st() or {}
    tick = p.get("tick") or 0
    if tick >= t0 and ts is None: ts, ks = time.time(), tick
    perf = p.get("perf") or {}
    if p.get("fps"): fps.append(p["fps"])
    if perf.get("dc"): dc.append(perf["dc"])
    if tick >= t1: break
    time.sleep(0.5)
if ts is None or not tick or tick <= ks:
    print("  sin progreso (scene=%s tick=%s)" % (p.get("scene"), p.get("tick"))); sys.exit(1)
print("  ticks/s=%.2f fps_med=%s dc_med=%s" % (
    (tick - ks) / (time.time() - ts),
    statistics.median(fps) if fps else "-",
    statistics.median(dc) if dc else "-"))
PY
}

for variant in "$@"; do
	echo "=== $variant ==="
	ssh "$HOST" "cat > $DIR/dev.sh <<EOF
export ENGINE=$DIR/odisea.frt.aarch64
export GODOT_OPTS=\"--replay $REPLAY\"
export ANNA_V2_BRIDGE=$IP:4999
export FRT_PERF=1
export $variant
EOF
sync; (sleep 1; reboot) >/dev/null 2>&1 &" 2>/dev/null
	sleep 105
	wait_game || { echo "  el juego no conecto"; continue; }
	measure
	ssh "$HOST" "grep -a FRT_PERF $DIR/log.txt | tail -1" 2>/dev/null | sed 's/^/  /'
done
