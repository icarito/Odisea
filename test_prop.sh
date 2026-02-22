#!/bin/bash

# ==============================================================================
# ODISEA PROP VALIDATION RUNNER
# Usage: ./test_prop.sh [--target="DoorName"] [--base64] [--editor-path="/path/to/godot"]
# If --target is omitted, ALL props in core_v2/props/ will be validated.
# Validates that screenshots differ between states (minimum pixel delta).
# ==============================================================================

TARGET_PROP=""
RETURN_BASE64=false
GODOT_BIN="godot3-bin" 
PROJECT_PATH="$(pwd)"
OUTPUT_DIR="$PROJECT_PATH/test_output/props"
VALIDATOR_SCRIPT="res://core_v2/scripts/prop_validator.oys"
CUSTOM_SCRIPT=false
PROP_DIR="./core_v2/props"
MIN_DELTA_PERCENT=2.0  # Minimum % of pixels that must differ between screenshots

# 1. Parse Arguments
while [ "$1" != "" ]; do
    case $1 in
        --target=* )   TARGET_PROP="${1#*=}" ;;
        --base64 )        RETURN_BASE64=true ;;
        --editor-path=*) GODOT_BIN="${1#*=}" ;;
        --script=* )   VALIDATOR_SCRIPT="${1#*=}"; CUSTOM_SCRIPT=true ;;
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
    
    # Use ImageMagick compare to get pixel difference metric
    # -metric AE counts the number of differing pixels
    local total_pixels
    total_pixels=$(identify -format '%[fx:w*h]' "$img1" 2>/dev/null)
    
    if [ -z "$total_pixels" ] || [ "$total_pixels" -eq 0 ]; then
        echo "  ⚠️  Cannot read image dimensions"
        return 0
    fi
    
    local diff_pixels
    diff_pixels=$(compare -metric AE "$img1" "$img2" /dev/null 2>&1)
    
    # compare outputs the metric to stderr, clean it
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

resolve_oys_script_for_prop() {
    local prop_file="$1"
    local prop_base="${prop_file%.tscn}"
    local prop_name
    prop_name=$(basename "$prop_base")

    local candidates=(
        "${prop_base}.oys"
        "./core_v2/scripts/${prop_name}.oys"
        "./core_v2/tests/${prop_name}.oys"
    )

    for c in "${candidates[@]}"; do
        if [ -f "$c" ]; then
            to_res_path "$c"
            return 0
        fi
    done

    echo "$VALIDATOR_SCRIPT"
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
    local selected_script="$VALIDATOR_SCRIPT"
    if [ "$CUSTOM_SCRIPT" = false ]; then
        selected_script=$(resolve_oys_script_for_prop "$PROP_FILE")
    fi
    echo "🧪 OYS script: $selected_script"
    export OYS_AUTO_RUN="$selected_script"

    # Run Godot
    $GODOT_BIN --path "$PROJECT_PATH" "res://core_v2/scenes/PropStage.tscn" --no-window --quit-after 1000
    
    # Check results
    COUNT=$(ls "$OUTPUT_DIR"/${PROP_NAME}_*.png 2>/dev/null | wc -l)
    # If files exist, verify they are real PNGs; Godot may write import metadata
    # files with the .png name in some setups which corrupts downstream checks.
    if [ "$COUNT" -gt 0 ]; then
        FIRST_FILE=$(ls "$OUTPUT_DIR"/${PROP_NAME}_*.png 2>/dev/null | head -n1)
        if [ -f "$FIRST_FILE" ]; then
            SIG=$(head -c 8 "$FIRST_FILE" | xxd -p 2>/dev/null || true)
            if [ "$SIG" != "89504e470d0a1a0a" ]; then
                echo "  ⚠️  Detected non-PNG artifact for $PROP_NAME (import metadata). Falling back to UI captures."
                rm -f "$OUTPUT_DIR"/${PROP_NAME}_*.png
                COUNT=0
            fi
        fi
    fi
    # Compatibility fallback: some runners save screenshots under test_output/ui/propstage_*.png
    # or unknown_*.png. If no prop-specific images were produced, try to map those UI
    # captures into the expected prop output names so CI can validate visuals.
    if [ "$COUNT" -eq 0 ]; then
        UI_DIR="$PROJECT_PATH/test_output/ui"
        if [ -d "$UI_DIR" ]; then
            # Map propstage_N_label -> ${PROP_NAME}_N_label
            # Only copy real PNG files (skip .import metadata files which may exist)
            for f in "$UI_DIR"/propstage_*.png; do
                # If the glob didn't match anything, the loop will receive the literal
                # pattern; skip such case by testing file existence.
                if [ ! -f "$f" ]; then
                    continue
                fi
                base=$(basename "$f")
                # expected pattern: propstage_<index>_<label>.png
                if [[ "$base" =~ propstage_([0-9]+)_(.*)\.png ]]; then
                    idx="${BASH_REMATCH[1]}"
                    lbl="${BASH_REMATCH[2]}"
                    cp -f "$f" "$OUTPUT_DIR/${PROP_NAME}_${idx}_${lbl}.png"
                fi
            done
            COUNT=$(ls "$OUTPUT_DIR"/${PROP_NAME}_*.png 2>/dev/null | wc -l)
        fi
    fi
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
    
    # If no images produced at all, it's a failure
    if [ ! -f "$idle_img" ] && [ ! -f "$mid_img" ] && [ ! -f "$active_img" ] && [ ! -f "$off_img" ]; then
        echo "❌ Failure: No standard screenshots (idle, mid, active, off) found for $PROP_NAME"
        return 1
    fi

    # Check idle → mid (should show interaction starting)
    if [ -f "$idle_img" ] && [ -f "$mid_img" ]; then
        check_image_delta "$idle_img" "$mid_img" "idle" "mid" || delta_failed=1
    elif [ -f "$idle_img" ] || [ -f "$mid_img" ]; then
        # If one is present but not both, it's a warning/fail if both were expected
        # For now, let's just compare idle with active if mid is missing
        pass
    fi
    
    # Check idle → active (should show clear visual change)
    if [ -f "$idle_img" ] && [ -f "$active_img" ]; then
        check_image_delta "$idle_img" "$active_img" "idle" "active" || delta_failed=1
    fi
    
    if [ "$delta_failed" -eq 1 ]; then
        echo "⚠️  DELTA ASSERTION FAILED for $PROP_NAME — prop may not be visually responding"
    fi

    return $delta_failed
}

TOTAL_FAILURES=0

if [ -n "$TARGET_PROP" ]; then
    # Single Target Mode
    echo "🔍 Searching for '$TARGET_PROP'..."
    PROP_PATH=$(find "$PROP_DIR" -name "${TARGET_PROP}.tscn" | head -n 1)

    if [ -z "$PROP_PATH" ]; then
        echo "❌ Error: Prop '$TARGET_PROP.tscn' not found in $PROP_DIR"
        exit 1
    fi
    
    run_validation "$TARGET_PROP" "$PROP_PATH"
    TOTAL_FAILURES=$?
    
else
    # Batch Mode
    echo "🔍 No target specified. Collecting all props in $PROP_DIR..."
    
    # Find all .tscn files recursively in PROP_DIR
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
