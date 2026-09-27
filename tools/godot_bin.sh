#!/bin/sh
# Imprime el binario de Godot que este proyecto debe usar: el del fork
# (icarito/godot-box3d-3), nunca el stock.
#
# Por que solo ese: el binario stock no trae el modulo Box3D (el proyecto cae a
# Bullet en silencio), y cualquier editor que no declare las settings del fork las
# BORRA de project.godot al salir -- tambien con --no-window --script.
#
# Por defecto: el binario del release que fija .github/box3d_release, bajado una
# vez a ~/.cache/odisea-godot/<release>/ (editor si hay display, headless si no).
# Es lo mismo que usa CI y no depende del estado del checkout del fork: cambiar de
# rama en el fork ya no dispara una recompilacion del motor.
#
# ODISEA_ENGINE=fork: construye y usa el editor del checkout local del fork, para
# trabajo de motor todavia no publicado. Se reconstruye si algun patch, el modulo
# box3d o scripts/build.sh es mas nuevo que el binario (build.sh reaplica los
# patches desde un checkout limpio, asi que el editor coincide exacto con el fork;
# con cache de scons, volver a un estado ya compilado es incremental).
# Detalle: docs/local-build-workflow.md del fork.
#
# Variables:
#   ODISEA_GODOT_BIN    override explicito, sin chequeos
#   ODISEA_ENGINE       release (default) o fork
#   ODISEA_GODOT_FLAVOR headless fuerza el mismo binario Server pinneado que usa CI
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
REQUESTED_FLAVOR="${ODISEA_GODOT_FLAVOR:-}"
ENGINE="${ODISEA_ENGINE:-release}"

if [ "$ENGINE" != "release" ] && [ "$ENGINE" != "fork" ]; then
    echo "godot_bin: ODISEA_ENGINE debe ser release o fork." >&2
    exit 1
fi

if [ -n "$REQUESTED_FLAVOR" ] && [ "$REQUESTED_FLAVOR" != "headless" ] && [ "$REQUESTED_FLAVOR" != "editor" ]; then
    echo "godot_bin: ODISEA_GODOT_FLAVOR debe ser headless o editor." >&2
    exit 1
fi

# Release (default, y siempre sin checkout del fork: CI, sesiones cloud): el binario
# que fija .github/box3d_release, bajado una vez a un cache. Headless si no hay
# display -- es un build platform=server, corre en un runner pelado --; el editor si lo hay.
if [ "$ENGINE" = "release" ] || [ "$REQUESTED_FLAVOR" = "headless" ] || [ ! -x "$FORK_DIR/scripts/build.sh" ]; then
    RELEASE="$(cat "$(dirname "$0")/../.github/box3d_release" 2>/dev/null)"
    if [ -z "$RELEASE" ]; then
        echo "godot_bin: sin fork en $FORK_DIR y sin .github/box3d_release." >&2
        exit 1
    fi
    FLAVOR="$REQUESTED_FLAVOR"
    if [ -z "$FLAVOR" ]; then
        if [ -n "$DISPLAY" ]; then FLAVOR=editor; else FLAVOR=headless; fi
    fi
    CACHE="${ODISEA_GODOT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/odisea-godot}/$RELEASE"
    REL_BIN="$CACHE/godot.box3d.linux.x86_64.$FLAVOR"
    if [ ! -x "$REL_BIN" ]; then
        mkdir -p "$CACHE"
        exec 8>"$CACHE/.download.lock"
        flock 8
        if [ ! -x "$REL_BIN" ]; then
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
