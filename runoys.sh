#!/bin/sh
# runoys.sh - Run an OYS test script
# Usage: ./runoys.sh path/to/test.oys

if [ -z "$1" ]; then
    echo "Usage: $0 path/to/test.oys"
    exit 1
fi

OYS_FILE="$1"

if [ ! -f "$OYS_FILE" ]; then
    echo "Error: File not found: $OYS_FILE"
    exit 1
fi

if [ -z "$GODOT_BIN" ]; then
    GODOT_BIN="godot3-bin"
fi

# Extract LEVEL from the .oys file
SCENE=$(grep -m1 "^LEVEL" "$OYS_FILE" | sed 's/LEVEL //')

if [ -z "$SCENE" ]; then
    SCENE="res://core_v2/levels/TestScene_v2.tscn"
    echo "No LEVEL found, using default: $SCENE"
fi

echo "Running: $OYS_FILE"
echo "Scene: $SCENE"
echo "---"

$GODOT_BIN --scene "$SCENE" --replay "$OYS_FILE"
