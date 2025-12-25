#!/bin/sh

if [ -z "$GODOT_BIN" ]; then
    echo "'GODOT_BIN' is not set."
    echo "Please set the environment variable  'export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot'"
    exit 1
fi

# we not use no-window because of issue https://github.com/godotengine/godot/issues/55379
#$GODOT_BIN --no-window -s -d ./addons/gdUnit3/bin/GdUnitCmdTool.gd $*
# Redirigimos stderr a stdout (2>&1) para ver toda la salida en los logs de CI
$GODOT_BIN -s -d ./addons/gdUnit3/bin/GdUnitCmdTool.gd $* 2>&1
exit_code=$?
$GODOT_BIN --no-window --quiet -s -d ./addons/gdUnit3/bin/GdUnitCopyLog.gd $* > /dev/null
exit $exit_code
