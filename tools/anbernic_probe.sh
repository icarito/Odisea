#!/usr/bin/env bash
# anbernic_probe.sh — banco de medición del Anbernic RG351V (FD-299, Fase 0).
#
# Mide una ventana de N segundos sobre el juego que corre en el dispositivo:
# faults de GPU (delta de dmesg), páginas GPU del kctx más grande, MemAvailable,
# captura grim y último heartbeat del central (host Unix).
#
#   tools/anbernic_probe.sh [etiqueta] [segundos=60]
#   PORTMASTER_HOST=root@otro.local tools/anbernic_probe.sh h1_msaa 60
#
# Salida: línea TSV en /tmp/odisea_probe/results.tsv y captura en
# /tmp/odisea_probe/<etiqueta>.png. La cobertura 3D se anota a ojo en plan.md.
set -euo pipefail

ETIQUETA="${1:?uso: anbernic_probe.sh <etiqueta> [segundos=60]}"
SECS="${2:-60}"
HOST="${PORTMASTER_HOST:-root@angel.local}"
OUT=/tmp/odisea_probe
TSV="$OUT/results.tsv"
ENV_GRIM="XDG_RUNTIME_DIR=/var/run/0-runtime-dir WAYLAND_DISPLAY=wayland-1"

mkdir -p "$OUT"

# Faults, memoria y captura, en una sola sesión SSH (el sleep corre allá).
# El ring de dmesg rota: se cuentan los faults con timestamp kernel posterior
# al uptime de arranque de la ventana, no por delta del total acumulado.
read -r FAULTS GPU_PAGES MEMAVAIL_KB < <(ssh "$HOST" "
  t0=\$(awk '{print \$1}' /proc/uptime); sleep $SECS
  f=\$(dmesg | grep 'GPU fault' | awk -v t0=\$t0 '{ts=substr(\$1,2,length(\$1)-2)+0; if (ts>t0) n++} END{print n+0}')
  pages=\$(awk 'NR==1{print \$2}' /sys/kernel/debug/mali0/gpu_memory)
  avail=\$(awk '/MemAvailable/{print \$2}' /proc/meminfo)
  echo \$f \$pages \$avail")
GRIM_SHOT=$(mktemp --suffix=.png)
ssh "$HOST" "$ENV_GRIM grim /tmp/odisea_probe_shot.png" >/dev/null
scp -q "$HOST:/tmp/odisea_probe_shot.png" "$GRIM_SHOT"
mv "$GRIM_SHOT" "$OUT/$ETIQUETA.png"

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
