#!/usr/bin/env bash
# Arma el paquete PortMaster de Odisea a partir de un .pck ya exportado.
#
#   tools/build_portmaster.sh <ruta/al/odisea.pck> [salida.zip] [binario.frt.aarch64]
#
# El tercer argumento es opcional: el binario FRT propio (con el modulo Box3D).
# Si se pasa, el paquete no depende del runtime frt_3.6 de PortMaster y port.json
# declara arch aarch64 en vez de runtime. Sin el, el port corre sobre el runtime
# stock y la fisica cae a Bullet en silencio.
#
# Fuentes (tracked): portmaster/  -- lanzador, port.json, gameinfo.xml, ini, README.
# Salida (gitignored): ports/  -- el arbol desempaquetado, listo para rsync al
# dispositivo, mas el .zip para publicar.
#
# El arbol que se arma es el que produce el instalador de PortMaster:
#
#   Odisea.sh
#   odisea/
#     odisea.pck  odisea.ini  port.json  gameinfo.xml  README.md
#     screenshot.png  BUILD.txt  licenses/
#
# Los mismos archivos fuente, con port.json/gameinfo.xml/screenshot en la raiz,
# son el layout que espera un PR a PortsMaster/PortMaster-New.
set -euo pipefail

PORT=odisea
SCRIPT=Odisea.sh

cd "$(dirname "$0")/.."
SRC=portmaster
OUT=ports

PCK="${1:?uso: build_portmaster.sh <odisea.pck> [salida.zip]}"
ZIP="$(realpath -m "${2:-$OUT/$PORT.zip}")"
ENGINE="${3:-}"
[ -s "$PCK" ] || { echo "ERROR: $PCK no existe o esta vacio" >&2; exit 1; }

# En CI llega PORT_VERSION (lleva el numero de run: 0.4.0-nightly.601+sha); en el
# checkout de CI no hay build_meta.json y git describe daba el sha "-dirty".
VERSION="${PORT_VERSION:-}"
[ -n "$VERSION" ] || VERSION="$(python3 -c 'import json,sys;print(json.load(open("build_meta.json"))["game_version"])' 2>/dev/null \
           || git describe --tags --always --dirty 2>/dev/null || echo local)"

rm -rf "$OUT/$PORT" "$OUT/$SCRIPT"
mkdir -p "$OUT/$PORT/licenses"
# ports/ vive dentro del proyecto: sin esto Godot importa el screenshot y el
# .pck copiado, y deja .import sueltos que terminan en el paquete.
touch "$OUT/.gdignore"

install -m 755 "$SRC/$SCRIPT" "$OUT/$SCRIPT"
install -m 644 "$SRC/port.json" "$SRC/gameinfo.xml" "$SRC/README.md" "$OUT/$PORT/"
install -m 644 "$SRC/$PORT.ini" "$OUT/$PORT/"
install -m 644 "$SRC/lowend.cfg" "$OUT/$PORT/"
install -m 644 "$PCK" "$OUT/$PORT/$PORT.pck"
install -m 644 CREDITS.md "$OUT/$PORT/licenses/CREDITS.md"
echo "$VERSION" > "$OUT/$PORT/BUILD.txt"

# Binario propio (opcional). Con el, el port declara arch en vez de runtime: esa es
# la distincion que usa PortMaster para saber si tiene que bajar un engine.
if [ -n "$ENGINE" ]; then
  [ -s "$ENGINE" ] || { echo "ERROR: $ENGINE no existe o esta vacio" >&2; exit 1; }
  install -m 755 "$ENGINE" "$OUT/$PORT/$PORT.frt.aarch64"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["attr"]["runtime"]=[]; d["attr"]["arch"]=["aarch64"]; json.dump(d,open(p,"w"),indent=2)' \
    "$OUT/$PORT/port.json"
  echo "Motor propio: $(basename "$ENGINE") ($(du -h "$ENGINE" | cut -f1)) -- port.json sin runtime, arch=aarch64"
else
  echo "Sin binario propio: el port usara el runtime frt_3.6 de PortMaster (fisica Bullet, no Box3D)."
fi

# Numero de run de CI en el titulo: PortMaster detecta el update por el md5 del zip,
# pero no muestra ninguna version; asi se ve cual nightly esta instalado.
if [ -n "${PORT_BUILD:-}" ]; then
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["attr"]["title"]+=f" (nightly {sys.argv[2]})"; json.dump(d,open(p,"w"),indent=2)' \
    "$OUT/$PORT/port.json" "$PORT_BUILD"
fi

# La captura es requisito de PortMaster (4:3, minimo 640x480) pero no bloquea un
# build local: se avisa y sigue.
if [ -f "$SRC/screenshot.png" ]; then
  install -m 644 "$SRC/screenshot.png" "$OUT/$PORT/"
else
  echo "AVISO: falta $SRC/screenshot.png (4:3, >=640x480). Requisito para el PR a PortMaster."
fi

# El lanzador referencia el nombre del port en varias rutas; si alguien renombra
# el directorio sin tocar el script, el port arranca y muere sin explicacion.
grep -q "ports/$PORT\b" "$OUT/$SCRIPT" || { echo "ERROR: $SCRIPT no apunta a ports/$PORT" >&2; exit 1; }
grep -q "$PORT.pck" "$OUT/$SCRIPT" || { echo "ERROR: $SCRIPT no carga $PORT.pck" >&2; exit 1; }
# Politica PortMaster: gptokeyb2 (.ini), no gptokeyb clasico (.gptk).
grep -q 'GPTOKEYB2' "$OUT/$SCRIPT" || { echo "ERROR: $SCRIPT no usa \$GPTOKEYB2" >&2; exit 1; }
grep -q "$PORT.ini" "$OUT/$SCRIPT" || { echo "ERROR: $SCRIPT no carga $PORT.ini" >&2; exit 1; }
# Los ajustes de handhelds lentos (FD-299) viajan siempre: Odisea.sh los instala como
# override.cfg solo en la generacion RK3326. Sin ellos ahi FRT corre con la configuracion de
# escritorio (MSAA, HDR, sombras pesadas) y el GPU sufre.
grep -q "framebuffer_allocation.mobile" "$OUT/$PORT/lowend.cfg" || { echo "ERROR: lowend.cfg sin el bloque FD-299" >&2; exit 1; }
grep -q "cp lowend.cfg override.cfg" "$OUT/$SCRIPT" || { echo "ERROR: $SCRIPT no instala lowend.cfg en los handhelds lentos" >&2; exit 1; }
python3 -c "
import json,sys
a=json.load(open('$SRC/port.json'))
assert a['items']==['$SCRIPT','$PORT'], a['items']
assert a['name']=='$PORT.zip', a['name']
assert a['attr']['runtime'], 'sin runtime: PortMaster no bajaria el engine'
assert all(not r.endswith('.squashfs') for r in a['attr']['runtime']), 'runtime debe ser la clave del catalogo (frt_3.6), no el archivo (.squashfs)'
"

rm -f "$ZIP"
mkdir -p "$(dirname "$ZIP")"
( cd "$OUT" && zip -qr9 "$ZIP" "$SCRIPT" "$PORT" )
echo "PortMaster $VERSION -> $ZIP ($(du -h "$ZIP" | cut -f1)), arbol en $OUT/"
