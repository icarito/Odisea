#!/bin/bash

# replay.sh - CLI wrapper for Godot replay recording and playback
# Usage:
# ./replay.sh record --name my_replay --duration 30
# ./replay.sh play --file res://tests/replays/my_replay.json

GODOT_BIN="godot3-bin"  # Adjust if needed
PROJECT_PATH="."
SCRIPT_PATH="scripts/replay/ReplayCliPlayer.gd"
SCENE_PATH="tests/fixtures/TestScene.tscn"

if [ "$1" == "record" ]; then
    shift
    NAME=""
    DURATION="10"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                NAME="$2"
                shift 2
                ;;
            --duration)
                DURATION="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    if [ -z "$NAME" ]; then
        echo "Error: --name required for record"
        exit 1
    fi
    $GODOT_BIN --path $PROJECT_PATH --scene $SCENE_PATH --script $SCRIPT_PATH --record --name $NAME --duration $DURATION --quit
elif [ "$1" == "play" ]; then
    shift
    FILE=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --file)
                FILE="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    if [ -z "$FILE" ]; then
        echo "Error: --file required for play"
        exit 1
    fi
    $GODOT_BIN --path $PROJECT_PATH --scene $SCENE_PATH --script $SCRIPT_PATH --replay $FILE --quit
else
    echo "Usage: $0 {record|play} [options]"
    echo "Record: $0 record --name <name> --duration <seconds>"
    echo "Play: $0 play --file <replay.json>"
    exit 1
fi