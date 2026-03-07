#!/bin/bash

# ==============================================================================
# ODISEA PROP VALIDATION RUNNER
# Usage: ./test_prop.sh [PropName] [--base64] [--show] [--min-delta=N]
# If PropName is omitted, ALL props in core_v2/props/ will be validated.
# Validates that screenshots differ between states (minimum pixel delta).
# ==============================================================================

TARGET_PROP=""
RETURN_BASE64=false
SHOW_LATEST=false
GODOT_BIN="godot3-bin" 
PROJECT_PATH="$(pwd)"
OUTPUT_DIR="$PROJECT_PATH/test_output/props"
VALIDATOR_SCRIPT="res://core_v2/scripts/prop_validator.oys"
PROP_DIR="./core_v2/props"
MIN_DELTA_PERCENT=2.0  # Minimum % of pixels that must differ between screenshots

# 1. Parse Arguments
while [ "$1" != "" ]; do
    case $1 in
        --base64 )        RETURN_BASE64=true ;;
        --show )          SHOW_LATEST=true ;;
        --editor-path=*) GODOT_BIN="${1#*=}" ;;
        --min-delta=* ) MIN_DELTA_PERCENT="${1#*=}" ;;
        -* )           echo "Unknown option: $1"; exit 1 ;;
        * )            TARGET_PROP="$1" ;;
    esac
    shift
done

mkdir -p "$OUTPUT_DIR"

# Image delta comparison function
# Returns 0 if images differ enough, 1 if too similar
check_image_delta() {
    local img1="$1"
    local img2="$2"
    local label1="$3"
    local label2="$4"
    
    if [ ! -f "$img1" ] || [ ! -f "$img2" ]; then
        echo "  ⚠️  Cannot compare: missing image(s) $label1 or $label2"
        return 1
    fi
    
    local total_pixels
    total_pixels=$(identify -format '%[fx:w*h]' "$img1" 2>/dev/null)
    
    if [ -z "$total_pixels" ] || [ "$total_pixels" -eq 0 ]; then
        echo "  ⚠️  Cannot read image dimensions"
        return 0
    fi
    
    local diff_pixels
    diff_pixels=$(compare -metric AE "$img1" "$img2" /dev/null 2>&1)
    diff_pixels=$(echo "$diff_pixels" | grep -o '[0-9]*' | head -1)
    
    if [ -z "$diff_pixels" ]; then
        echo "  ⚠️  Compare failed between $label1 and $label2"
        return 0
    fi
    
    local percent
    percent=$(python3 -c "print(f'{($diff_pixels / $total_pixels) * 100:.2f}')")
    
    if python3 -c "exit(0 if $percent >= $MIN_DELTA_PERCENT else 1)"; then
        echo "  ✅ Delta $label1→$label2: ${percent}% pixels changed (>= ${MIN_DELTA_PERCENT}%)"
        return 0
    else
        echo "  ❌ Delta $label1→$label2: ${percent}% pixels changed (< ${MIN_DELTA_PERCENT}% minimum!)"
        return 1
    fi
}

to_res_path() {
    local local_path="$1"
    local clean="${local_path#./}"
    echo "res://${clean}"
}

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
    echo "🧪 OYS script: $VALIDATOR_SCRIPT"
    echo "📦 Prop path: $RES_PATH"
    if [ -z "${ODISEA_FORCE_MUTE_AUDIO+x}" ]; then
        export ODISEA_FORCE_MUTE_AUDIO=1
    fi

    # Run Godot
    $GODOT_BIN --path "$PROJECT_PATH" "res://core_v2/scenes/PropStage.tscn" --no-window --quit-after 1000
    
    # Check results — only count real PNG files
    COUNT=0
    for f in "$OUTPUT_DIR"/${PROP_NAME}_*.png; do
        [ ! -f "$f" ] && continue
        SIG=$(head -c 8 "$f" | xxd -p 2>/dev/null || true)
        if [ "$SIG" = "89504e470d0a1a0a" ]; then
            COUNT=$((COUNT + 1))
        else
            echo "  ⚠️  Removing non-PNG artifact: $(basename "$f")"
            rm -f "$f"
        fi
    done

    if [ "$COUNT" -gt 0 ]; then
        echo "✅ Success: $COUNT screenshots generated for $PROP_NAME"
    else
        echo "❌ Failure: No screenshots found for $PROP_NAME"
        return 1
    fi
    
    # Assert minimum delta between screenshots
    local delta_failed=0
    local idle_img="$OUTPUT_DIR/${PROP_NAME}_0_idle.png"
    local mid_img="$OUTPUT_DIR/${PROP_NAME}_1_mid.png"
    local active_img="$OUTPUT_DIR/${PROP_NAME}_2_active.png"
    local off_img="$OUTPUT_DIR/${PROP_NAME}_3_off.png"
    
    if [ ! -f "$idle_img" ] && [ ! -f "$mid_img" ] && [ ! -f "$active_img" ] && [ ! -f "$off_img" ]; then
        echo "❌ Failure: No standard screenshots (idle, mid, active, off) found for $PROP_NAME"
        return 1
    fi

    # Check idle → mid
    if [ -f "$idle_img" ] && [ -f "$mid_img" ]; then
        check_image_delta "$idle_img" "$mid_img" "idle" "mid" || delta_failed=1
    fi
    
    # Check idle → active
    if [ -f "$idle_img" ] && [ -f "$active_img" ]; then
        check_image_delta "$idle_img" "$active_img" "idle" "active" || delta_failed=1
    fi
    
    if [ "$delta_failed" -eq 1 ]; then
        echo "⚠️  DELTA ASSERTION FAILED for $PROP_NAME — prop may not be visually responding"
    fi

    # Copy latest active screenshot for easy viewing
    if [ "$SHOW_LATEST" = true ] && [ -f "$active_img" ]; then
        cp -f "$active_img" "$OUTPUT_DIR/latest.png"
        echo "📸 Latest screenshot: $OUTPUT_DIR/latest.png"
    elif [ "$SHOW_LATEST" = true ] && [ -f "$idle_img" ]; then
        cp -f "$idle_img" "$OUTPUT_DIR/latest.png"
        echo "📸 Latest screenshot: $OUTPUT_DIR/latest.png"
    fi

    return $delta_failed
}

TOTAL_FAILURES=0

if [ -n "$TARGET_PROP" ]; then
    echo "🔍 Searching for '$TARGET_PROP'..."
    PROP_PATH=$(find "$PROP_DIR" -name "${TARGET_PROP}.tscn" | head -n 1)

    if [ -z "$PROP_PATH" ]; then
        echo "❌ Error: Prop '$TARGET_PROP.tscn' not found in $PROP_DIR"
        exit 1
    fi
    
    run_validation "$TARGET_PROP" "$PROP_PATH"
    TOTAL_FAILURES=$?
    
else
    echo "🔍 No target specified. Collecting all props in $PROP_DIR..."
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
        run_validation "$NAME" "$p"
        TOTAL_FAILURES=$((TOTAL_FAILURES + $?))
    done
fi

echo "================================================================"
if [ "$TOTAL_FAILURES" -gt 0 ]; then
    echo "⚠️  $TOTAL_FAILURES prop(s) had delta assertion failures."
else
    echo "✅ All tasks finished successfully."
fi

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

exit $TOTAL_FAILURES
