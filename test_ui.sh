#!/bin/bash

# ==============================================================================
# ODISEA UI VALIDATION RUNNER
# Usage:
#   ./test_ui.sh --scene="DebugOverlay" --base64
#   ./test_ui.sh --scene="res://core_v2/ui/retro/DebugOverlay.tscn"
# ==============================================================================

TARGET_UI="DebugOverlay"
RETURN_BASE64=false
GODOT_BIN="godot3-bin"
PROJECT_PATH="$(pwd)"
OUTPUT_DIR="$PROJECT_PATH/test_output/ui"
VALIDATOR_SCRIPT="res://core_v2/scripts/ui_validator.oys"
CUSTOM_SCRIPT=false
UI_SEARCH_DIRS=("./core_v2/ui" "./core_v2/things")

while [ "$1" != "" ]; do
    case $1 in
        --scene=* )       TARGET_UI="${1#*=}" ;;
        --base64 )        RETURN_BASE64=true ;;
        --editor-path=* ) GODOT_BIN="${1#*=}" ;;
        --script=* )      VALIDATOR_SCRIPT="${1#*=}"; CUSTOM_SCRIPT=true ;;
        -* )              echo "Unknown option: $1"; exit 1 ;;
        * )               TARGET_UI="$1" ;;
    esac
    shift
done

mkdir -p "$OUTPUT_DIR"

resolve_ui_path() {
    local target="$1"

    # Already a direct path?
    if [ -f "$target" ]; then
        echo "$target"
        return 0
    fi

    # res://path from project root
    if [[ "$target" == res://* ]]; then
        local local_path=".${target#res://}"
        if [ -f "$local_path" ]; then
            echo "$local_path"
            return 0
        fi
    fi

    # Name-based lookup
    local base="$target"
    base="${base##*/}"
    base="${base%.tscn}"

    local found
    for dir in "${UI_SEARCH_DIRS[@]}"; do
        found=$(find "$dir" -name "${base}.tscn" 2>/dev/null | head -n 1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    done

    return 1
}

to_res_path() {
    local local_path="$1"
    local clean="${local_path#./}"
    echo "res://${clean}"
}

resolve_oys_script_for_ui() {
    local ui_path="$1"
    local ui_base="${ui_path%.tscn}"
    local ui_name
    ui_name=$(basename "$ui_base")

    local candidates=(
        "${ui_base}.oys"
        "./core_v2/scripts/${ui_name}.oys"
        "./core_v2/tests/${ui_name}.oys"
    )

    for c in "${candidates[@]}"; do
        if [ -f "$c" ]; then
            to_res_path "$c"
            return 0
        fi
    done

    echo "$VALIDATOR_SCRIPT"
}

UI_LOCAL_PATH=$(resolve_ui_path "$TARGET_UI")
if [ -z "$UI_LOCAL_PATH" ]; then
    echo "❌ Error: UI scene '$TARGET_UI' not found."
    exit 1
fi

UI_RES_PATH=$(to_res_path "$UI_LOCAL_PATH")
UI_NAME=$(basename "$UI_LOCAL_PATH" .tscn | tr '[:upper:]' '[:lower:]')

echo "----------------------------------------------------------------"
echo "🚀 Validating UI scene: $UI_RES_PATH"

echo "🧹 Cleaning previous screenshots for '$UI_NAME'..."
rm -f "$OUTPUT_DIR"/${UI_NAME}_*.png

export OYS_UI_SCENE="$UI_RES_PATH"
if [ "$CUSTOM_SCRIPT" = true ]; then
    OYS_SCRIPT="$VALIDATOR_SCRIPT"
else
    OYS_SCRIPT=$(resolve_oys_script_for_ui "$UI_LOCAL_PATH")
fi
echo "🧪 OYS script: $OYS_SCRIPT"
export OYS_AUTO_RUN="$OYS_SCRIPT"
if [ -z "${ODISEA_FORCE_MUTE_AUDIO+x}" ]; then
    export ODISEA_FORCE_MUTE_AUDIO=1
fi

$GODOT_BIN --path "$PROJECT_PATH" "$UI_RES_PATH" --no-window --quit-after 260
RUN_CODE=$?

if [ "$RUN_CODE" -ne 0 ]; then
    echo "❌ Godot execution failed with code $RUN_CODE"
    exit "$RUN_CODE"
fi

COUNT=$(ls "$OUTPUT_DIR"/${UI_NAME}_*.png 2>/dev/null | wc -l)
if [ "$COUNT" -eq 0 ]; then
    echo "❌ Failure: No UI screenshots found for '$UI_NAME'"
    exit 1
fi

echo "✅ Success: $COUNT UI screenshots generated"

if [ "$RETURN_BASE64" = true ]; then
    IMAGES=$(ls "$OUTPUT_DIR"/${UI_NAME}_*.png 2>/dev/null | sort)
    if [ -n "$IMAGES" ]; then
        echo "📦 Encoding UI screenshots..."
        for img in $IMAGES; do
            name=$(basename "$img")
            echo "---BEGIN_BASE64_IMAGE:$name---"
            base64 -w 0 "$img"
            echo -e "\n---END_BASE64_IMAGE---"
        done
    else
        echo "⚠️ No screenshots found to encode"
    fi
else
    echo "📁 UI artifacts: $OUTPUT_DIR"
fi

echo "----------------------------------------------------------------"
exit 0
