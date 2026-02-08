#!/bin/bash

# ==============================================================================
# ODISEA PROP VALIDATION RUNNER
# Usage: ./test_prop.sh [--target="DoorName"] [--base64] [--editor-path="/path/to/godot"]
# If --target is omitted, ALL props in core_v2/props/ will be validated.
# ==============================================================================

TARGET_PROP=""
RETURN_BASE64=false
GODOT_BIN="godot3-bin" 
PROJECT_PATH="$(pwd)"
OUTPUT_DIR="$PROJECT_PATH/test_output/props"
VALIDATOR_SCRIPT="res://core_v2/tests/prop_validator.oys"
PROP_DIR="./core_v2/props"

# 1. Parse Arguments
while [ "$1" != "" ]; do
    case $1 in
        --target=* )   TARGET_PROP="${1#*=}" ;;
        --base64 )        RETURN_BASE64=true ;;
        --editor-path=*) GODOT_BIN="${1#*=}" ;;
        -* )           echo "Unknown option: $1"; exit 1 ;;
        * )            TARGET_PROP="$1" ;;
    esac
    shift
done

mkdir -p "$OUTPUT_DIR"

run_validation() {
    local PROP_NAME=$1
    local PROP_FILE=$2
    
    echo "----------------------------------------------------------------"
    echo "🚀 Validating: $PROP_NAME"
    
    # Clean previous screenshots for this prop
    rm -f "$OUTPUT_DIR"/${PROP_NAME}_*.png
    
    CLEAN_PATH="${PROP_FILE#./}"
    RES_PATH="res://$CLEAN_PATH"
    
    export OYS_PROP_PATH="$RES_PATH"
    export OYS_AUTO_RUN="$VALIDATOR_SCRIPT"

    # Run Godot
    # Filtering output to keep it clean, but showing errors if any
    $GODOT_BIN --path "$PROJECT_PATH" "res://core_v2/scenes/PropStage.tscn" --no-window --quit-after 200
    
    # Check results
    COUNT=$(ls "$OUTPUT_DIR"/${PROP_NAME}_*.png 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        echo "✅ Success: $COUNT screenshots generated for $PROP_NAME"
    else
        echo "❌ Failure: No screenshots found for $PROP_NAME"
    fi
}

if [ -n "$TARGET_PROP" ]; then
    # Single Target Mode
    echo "🔍 Searching for '$TARGET_PROP'..."
    PROP_PATH=$(find "$PROP_DIR" -name "${TARGET_PROP}.tscn" | head -n 1)

    if [ -z "$PROP_PATH" ]; then
        echo "❌ Error: Prop '$TARGET_PROP.tscn' not found in $PROP_DIR"
        exit 1
    fi
    
    run_validation "$TARGET_PROP" "$PROP_PATH"
    
else
    # Batch Mode
    echo "🔍 No target specified. Collecting all props in $PROP_DIR..."
    
    # Find all .tscn files in PROP_DIR
    PROPS=$(find "$PROP_DIR" -name "*.tscn")
    
    if [ -z "$PROPS" ]; then
        echo "❌ No props found in $PROP_DIR"
        exit 1
    fi
    
    echo "📋 Found the following props:"
    for p in $PROPS; do
        basename "$p" .tscn
    done
    echo "----------------------------------------------------------------"
    echo "🏁 Starting Batch Validation..."
    
    for p in $PROPS; do
        NAME=$(basename "$p" .tscn)
        # Call the function defined above
        run_validation "$NAME" "$p"
    done
fi

echo "================================================================"
echo "✅ All tasks finished."

if [ "$RETURN_BASE64" = true ] && [ -n "$TARGET_PROP" ]; then
    IMAGES=$(ls "$OUTPUT_DIR"/${TARGET_PROP}_*.png 2>/dev/null | sort)
    
    if [ -n "$IMAGES" ]; then
        echo "📦 Encoding all results for Agent..."
        for img in $IMAGES; do
            NAME=$(basename "$img")
            echo "---BEGIN_BASE64_IMAGE:$NAME---"
            base64 -w 0 "$img"
            echo -e "\n---END_BASE64_IMAGE---"
        done
    else
        echo "⚠️  No screenshots found to encode for $TARGET_PROP"
    fi
elif [ "$RETURN_BASE64" = true ]; then
    echo "⚠️  Base64 output is only supported in single-target mode."
else
    echo "📁 Validation artifacts: $OUTPUT_DIR"
fi
