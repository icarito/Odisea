#!/bin/sh
# Imprime el binario de Godot que este proyecto debe usar: el editor construido del
# fork (icarito/godot-box3d-3), y lo reconstruye antes si el fork cambio desde la
# ultima build.
#
# Por que solo ese: el binario stock no trae el modulo Box3D (el proyecto cae a
# Bullet en silencio), y cualquier editor que no declare las settings del fork las
# BORRA de project.godot al salir -- tambien con --no-window --script. Un build local
# viejo es tan peligroso como el stock, asi que aca "viejo" se reconstruye, no se usa.
#
# Viejo = algun patch, el modulo box3d o scripts/build.sh es mas nuevo que el
# binario. Commitear en el fork, hacer pull o agregar un patch alcanza para que el
# siguiente uso reconstruya; build.sh reaplica los patches desde un checkout limpio,
# asi que el editor resultante coincide exacto con el fork.
#
# Sin checkout del fork (CI, cloud) baja el binario del release de
# .github/box3d_release a ~/.cache/odisea-godot/<release>/.
#
# Variables:
#   ODISEA_GODOT_BIN    override explicito, sin chequeos
#   ODISEA_FORK_DIR     checkout de godot-box3d-3 (el clon de godot va al lado)
#   ODISEA_GODOT_CACHE  donde guardar el binario del release
#   SCONS_CACHE       se respeta si esta definido
#
# La salida de la build va a stderr: stdout es solo la ruta, porque los scripts
# hacen GODOT_BIN="$(sh tools/godot_bin.sh)".

if [ -n "$ODISEA_GODOT_BIN" ]; then
    printf '%s\n' "$ODISEA_GODOT_BIN"
    exit 0
fi

FORK_DIR="${ODISEA_FORK_DIR:-/run/media/icarito/DATA/icarito/Proyectos/godot3-box3d/godot-box3d-3}"
BIN="$(dirname "$FORK_DIR")/godot/bin/godot.x11.opt.tools.64"

# Sin checkout del fork (CI, sesiones cloud): el binario del release que fija
# .github/box3d_release, bajado una vez a un cache. Headless si no hay display --
# es un build platform=server, corre en un runner pelado --; el editor si lo hay.
if [ ! -x "$FORK_DIR/scripts/build.sh" ]; then
    RELEASE="$(cat "$(dirname "$0")/../.github/box3d_release" 2>/dev/null)"
    if [ -z "$RELEASE" ]; then
        echo "godot_bin: sin fork en $FORK_DIR y sin .github/box3d_release." >&2
        exit 1
    fi
    if [ -n "$DISPLAY" ]; then FLAVOR=editor; else FLAVOR=headless; fi
    CACHE="${ODISEA_GODOT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/odisea-godot}/$RELEASE"
    REL_BIN="$CACHE/godot.box3d.linux.x86_64.$FLAVOR"
    if [ ! -x "$REL_BIN" ]; then
        mkdir -p "$CACHE"
        echo "godot_bin: bajando $FLAVOR de godot-box3d-3 $RELEASE..." >&2
        if ! curl -fsSL -o "$REL_BIN.part" \
            "https://github.com/icarito/godot-box3d-3/releases/download/$RELEASE/godot.box3d.linux.x86_64.$FLAVOR"; then
            rm -f "$REL_BIN.part"
            echo "godot_bin: no pude bajar el binario del release $RELEASE." >&2
            exit 1
        fi
        chmod +x "$REL_BIN.part"
        mv "$REL_BIN.part" "$REL_BIN"
    fi
    printf '%s\n' "$REL_BIN"
    exit 0
fi

is_stale() {
    [ ! -x "$BIN" ] && return 0
    [ -n "$(find "$FORK_DIR/patches" "$FORK_DIR/box3d" "$FORK_DIR/scripts/build.sh" \
        -newer "$BIN" -type f -not -path '*/.git/*' -print -quit 2>/dev/null)" ]
}

if is_stale; then
    # Un lock por fork: varios tests en paralelo esperan a una sola build en vez de
    # lanzar cuatro scons contra el mismo arbol.
    exec 9>"$(dirname "$FORK_DIR")/.godot_editor_build.lock"
    flock 9
    if is_stale; then
        echo "godot_bin: el fork cambio desde la ultima build; reconstruyendo el editor..." >&2
        if ! "$FORK_DIR/scripts/build.sh" editor >&2; then
            echo "godot_bin: fallo la build del editor del fork; no se usa uno viejo." >&2
            exit 1
        fi
        touch "$BIN"
    fi
fi

printf '%s\n' "$BIN"
