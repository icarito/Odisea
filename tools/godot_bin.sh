#!/bin/sh
# Imprime el binario de Godot que este proyecto debe usar.
#
# Orden:
#   1. $ODISEA_GODOT_BIN (override explícito)
#   2. El último editor compilado de nuestro fork (godot3-box3d/godot/bin),
#      prefiriendo la build opt.tools. Es el único que conoce Box3D y los
#      settings propios del fork: el 3.6.2 upstream pisa project.godot.
#   3. Fallback: el `godot3-bin` del sistema.
#
# El directorio del fork se puede mover con $ODISEA_FORK_BIN_DIR.

if [ -n "$ODISEA_GODOT_BIN" ]; then
    printf '%s\n' "$ODISEA_GODOT_BIN"
    exit 0
fi

FORK_BIN_DIR="${ODISEA_FORK_BIN_DIR:-/run/media/icarito/DATA/icarito/Proyectos/godot3-box3d/godot/bin}"

if [ -x "$FORK_BIN_DIR/godot.x11.opt.tools.64" ]; then
    printf '%s\n' "$FORK_BIN_DIR/godot.x11.opt.tools.64"
    exit 0
fi

newest=$(ls -t "$FORK_BIN_DIR"/godot.x11.opt.tools.* 2>/dev/null | head -n 1)
if [ -n "$newest" ] && [ -x "$newest" ]; then
    printf '%s\n' "$newest"
    exit 0
fi

printf '%s\n' "godot3-bin"
