#!/usr/bin/env bash
# anbernic_probe.sh — banco de medición del Anbernic RG351V (FD-299, Fase 0).
#
# Mide una ventana de N segundos sobre el juego que corre en el dispositivo:
# faults de GPU (delta de dmesg), páginas GPU del kctx más grande, MemAvailable,
# capturas grim en serie y último heartbeat del central (host Unix).
#
#   tools/anbernic_probe.sh [etiqueta] [segundos=60] [shots=1]
#   PORTMASTER_HOST=root@otro.local tools/anbernic_probe.sh h1_msaa 60 4
#
# Con shots>1 captura una serie (<etiqueta>_0..N.png repartidas en la ventana):
# la cobertura SOSTENIDA es la métrica — un frame completo aislado puede mentir.
# Salida: línea TSV en /tmp/odisea_probe/results.tsv y capturas en /tmp/odisea_probe/.
set -euo pipefail

ETIQUETA="${1:?uso: anbernic_probe.sh <etiqueta> [segundos=60] [shots=1]}"
SECS="${2:-60}"
SHOTS="${3:-1}"
HOST="${PORTMASTER_HOST:-root@angel.local}"
PEER="${ANNA_PEER_URL:-http://localhost:4999}"
OUT=/tmp/odisea_probe
TSV="$OUT/results.tsv"
ENV_GRIM="XDG_RUNTIME_DIR=/var/run/0-runtime-dir WAYLAND_DISPLAY=wayland-1"

mkdir -p "$OUT"
TMP_METRICS=$(mktemp)
trap 'rm -f "$TMP_METRICS"' EXIT

# ANNA_MOVE=1 rota el yaw de Elías entre capturas: contenido fresco en cada shot
# (con el jugador quieto los tiles abortados no se distinguen de contenido viejo).
anna_move() {
  local HB POSYAW
  HB=$(curl -s --max-time 10 "$PEER/status") || return 0
  POSYAW=$(python3 -c '
import json,sys
d=json.loads(sys.argv[1])
h=[v for v in (d.values() if isinstance(d,dict) else d) if isinstance(v,dict) and v.get("host")=="Unix"]
p=(max(h,key=lambda v:v.get("timestamp",0)) if h else {}).get("player") or {}
pos=p.get("position") or [0,0,0]
print(pos[0],pos[1],pos[2],p.get("yaw",0))
' "$HB" 2>/dev/null) || return 0
  [ -n "$POSYAW" ] || return 0
  read -r X Y Z YAW <<< "$POSYAW"
  NEWYAW=$(python3 -c "print($YAW + 0.55)")
  curl -s --max-time 10 -XPOST "$PEER/command" -H "Content-Type: application/json" \
    -d "{\"action\":\"teleport_player\",\"args\":{\"position\":[$X,$Y,$Z],\"yaw\":$NEWYAW}}" >/dev/null || true
}

# Faults, memoria y capturas en serie, en una sola sesión SSH (todo corre allá).
# El ring de dmesg rota: se cuentan los faults con timestamp kernel posterior
# al uptime de arranque de la ventana, no por delta del total acumulado.
# Las shots se reparten en la ventana: shot i a i*interval (la primera a t=0).
INTERVAL=$(( SECS / SHOTS ))
T0=$(ssh "$HOST" "awk '{print \$1}' /proc/uptime")
for i in $(seq 0 $((SHOTS-1))); do
  [ "$i" -gt 0 ] && [ "${ANNA_MOVE:-0}" = "1" ] && anna_move && sleep 1
  ssh "$HOST" "$ENV_GRIM grim /tmp/odisea_probe_shot_$i.png" >/dev/null
done
ssh "$HOST" "
  f=\$(dmesg | grep 'GPU fault' | awk -v t0=$T0 '{ts=substr(\$1,2,length(\$1)-2)+0; if (ts>t0) n++} END{print n+0}')
  pages=\$(awk 'NR==1{print \$2}' /sys/kernel/debug/mali0/gpu_memory)
  avail=\$(awk '/MemAvailable/{print \$2}' /proc/meminfo)
  echo \$f \$pages \$avail
" > "$TMP_METRICS"
read -r FAULTS GPU_PAGES MEMAVAIL_KB < "$TMP_METRICS"
for i in $(seq 0 $((SHOTS-1))); do
  scp -q "$HOST:/tmp/odisea_probe_shot_$i.png" "$OUT/$ETIQUETA.png" 2>/dev/null || true
  [ "$SHOTS" -gt 1 ] && scp -q "$HOST:/tmp/odisea_probe_shot_$i.png" "$OUT/${ETIQUETA}_$i.png" 2>/dev/null || true
done

# Último heartbeat del central con host Unix (nocturno => el dispositivo).
HB=$(set -a; source .env; set +a
  rtk proxy curl -s --max-time 15 -H "Authorization: Bearer $ODISEA_BRIDGE_TOKEN" \
    https://odisea.educa.juegos/status)
read -r FPS DC VTX NODES SCENE HB_TS < <(python3 -c '
import json,sys
d=json.loads(sys.argv[1])
hbs=[v for v in (d.values() if isinstance(d,dict) else d) if isinstance(v,dict) and v.get("host")=="Unix"]
h=max(hbs,key=lambda v:v.get("timestamp",0)) if hbs else {}
p=h.get("player") or {}; f=p.get("perf") or {}
print(p.get("fps","-"),f.get("dc","-"),f.get("vtx","-"),f.get("nodes","-"),p.get("scene","-"),h.get("timestamp","-"))
' "$HB")
FAULTS=$((FAULTS))
MEMAVAIL_MB=$((MEMAVAIL_KB/1024))

[ -f "$TSV" ] || printf 'etiqueta\tfecha\tbuild\tinstalado\tetiqueta_escena\tfaults_%ss\tpaginas_gpu\tmemavail_mb\tfps\tdc\tvtx\tnodos\tcobertura_3d\tnota\n' "$SECS" >> "$TSV"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$ETIQUETA" "$(date +%F_%H:%M)" \
  "$(ssh "$HOST" 'cat /storage/roms/ports/odisea/BUILD.txt' 2>/dev/null || echo '?')" \
  "$([ -n "$(ssh "$HOST" 'test -f /storage/roms/ports/odisea/override.cfg && echo si')" ] && echo override || echo sin_override)" \
  "$SCENE" "$FAULTS" "$GPU_PAGES" "$MEMAVAIL_MB" "$FPS" "$DC" "$VTX" "$NODES" "" "${NOTA:-}" >> "$TSV"

echo "[$ETIQUETA] escena=$SCENE faults/${SECS}s=$FAULTS gpu_pag=$GPU_PAGES memavail=${MEMAVAIL_MB}MB fps=$FPS dc=$DC vtx=$VTX nodos=$NODES captura=$OUT/$ETIQUETA.png"
