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
# Variables:
#   ODISEA_GODOT_BIN  override explicito, sin chequeos
#   ODISEA_FORK_DIR   checkout de godot-box3d-3 (el clon de godot va al lado)
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

if [ ! -x "$FORK_DIR/scripts/build.sh" ]; then
    echo "godot_bin: no encuentro el fork en $FORK_DIR (defina ODISEA_FORK_DIR)." >&2
    exit 1
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
