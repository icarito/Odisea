#!/bin/bash

# ==============================================================================
# ODISEA PROP VALIDATION RUNNER v2 — Prototyping Edition
# Usage: ./test_prop.sh [PropName] [--list] [--quick] [--base64] [--show]
#   --list      List all available props and exit
#   --quick     Single screenshot, no interaction (for rapid iteration)
#   --base64    Return screenshots as base64 for AI review
#   --show      Copy latest screenshot to test_output/props/latest.png
#   --min-delta=N  Set minimum pixel delta % (default 2.0)
# ==============================================================================

TARGET_PROP=""
RETURN_BASE64=false
SHOW_LATEST=false
QUICK_MODE=false
LIST_MODE=false
GODOT_BIN="${GODOT_BIN:-godot3-bin}"
PROJECT_PATH="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$PROJECT_PATH/test_output/props"
VALIDATOR_SCRIPT="res://core_v2/scripts/prop_validator.oys"
PROP_DIR="$PROJECT_PATH/core_v2/props"
MIN_DELTA_PERCENT=2.0

# 1. Parse Arguments
while [ "$1" != "" ]; do
    case $1 in
        --base64 )        RETURN_BASE64=true ;;
        --quick )         QUICK_MODE=true ;;
        --list )          LIST_MODE=true ;;
        --show )          SHOW_LATEST=true ;;
        --editor-path=*)  GODOT_BIN="${1#*=}" ;;
        --min-delta=* )   MIN_DELTA_PERCENT="${1#*=}" ;;
        -* )              echo "Unknown option: $1"; exit 1 ;;
        * )               TARGET_PROP="$1" ;;
    esac
    shift
done

# 2. List mode — show all props and exit
if [ "$LIST_MODE" = true ]; then
    echo "📋 Available props in $PROP_DIR:"
    echo ""
    for f in "$PROP_DIR"/*.tscn "$PROP_DIR"/**/*.tscn 2>/dev/null; do
        [ ! -f "$f" ] && continue
        local NAME=$(basename "$f" .tscn)
        local SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
        # Check if prop has a custom validator
        local VALIDATOR=""
        [ -f "${f%.tscn}.oys" ] && VALIDATOR="🎯 custom validator"
        [ -f "$PROJECT_PATH/core_v2/scripts/${NAME}.oys" ] && VALIDATOR="🎯 custom validator"
        printf "  %-35s %6d bytes  %s\n" "$NAME" "$SIZE" "$VALIDATOR"
    done
    echo ""
    echo "Usage: ./test_prop.sh <PropName> [--quick] [--show]"
    echo "       ./test_prop.sh --list"
    exit 0
fi

mkdir -p "$OUTPUT_DIR"

# Image delta comparison
check_image_delta() {
    local img1="$1"
    local img2="$2"
    local label1="$3"
    local label2="$4"
    
    if [ ! -f "$img1" ] || [ ! -f "$img2" ]; then
        echo "  ⚠️  Cannot compare: missing image(s)"
        return 1
    fi
    
    local total_pixels
    total_pixels=$(identify -format '%[fx:w*h]' "$img1" 2>/dev/null)
    
    if [ -z "$total_pixels" ] || [ "$total_pixels" -eq 0 ]; then
        echo "  ⚠️  Cannot read image dimensions (ImageMagick may not be installed)"
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
        echo "  ✅ Delta $label1→$label2: ${percent}% changed (>= ${MIN_DELTA_PERCENT}%)"
        return 0
    else
        echo "  ❌ Delta $label1→$label2: ${percent}% changed (< ${MIN_DELTA_PERCENT}%)"
        return 1
    fi
}

run_validation() {
    local PROP_NAME=$1
    local PROP_FILE=$2
    
    if [ "$QUICK_MODE" = true ]; then
        echo "⚡ Quick: $PROP_NAME"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🚀 Validating: $PROP_NAME"
    fi
    
    # Clean previous screenshots for this prop
    rm -f "$OUTPUT_DIR"/${PROP_NAME}_*.png
    
    CLEAN_PATH="${PROP_FILE#$PROJECT_PATH/}"
    RES_PATH="res://$CLEAN_PATH"
    
    export OYS_PROP_PATH="$RES_PATH"
    export OYS_AUTO_RUN="$VALIDATOR_SCRIPT"
    [ "$QUICK_MODE" = true ] && export OYS_QUICK_MODE="1"
    [ -z "${ODISEA_FORCE_MUTE_AUDIO+x}" ] && export ODISEA_FORCE_MUTE_AUDIO=1

    $GODOT_BIN --path "$PROJECT_PATH" "res://core_v2/scenes/PropStage.tscn" --no-window --quit-after 1000 2>/dev/null
    
    # Check results
    local COUNT=0
    for f in "$OUTPUT_DIR"/${PROP_NAME}_*.png; do
        [ ! -f "$f" ] && continue
        SIG=$(head -c 8 "$f" | xxd -p 2>/dev/null || true)
        if [ "$SIG" = "89504e470d0a1a0a" ]; then
            COUNT=$((COUNT + 1))
        else
            rm -f "$f"
        fi
    done

    if [ "$COUNT" -gt 0 ]; then
        if [ "$QUICK_MODE" = true ]; then
            echo "  ✅ $COUNT screenshot"
        else
            echo "  ✅ $COUNT screenshots generated"
        fi
    else
        echo "  ❌ No screenshots — prop may have failed to load"
        return 1
    fi
    
    # In quick mode, skip delta checks
    if [ "$QUICK_MODE" = true ]; then
        return 0
    fi
    
    # Delta checks for full mode
    local delta_failed=0
    local idle_img="$OUTPUT_DIR/${PROP_NAME}_0_idle.png"
    local mid_img="$OUTPUT_DIR/${PROP_NAME}_1_mid.png"
    local active_img="$OUTPUT_DIR/${PROP_NAME}_2_active.png"
    
    if [ -f "$idle_img" ] && [ -f "$mid_img" ]; then
        check_image_delta "$idle_img" "$mid_img" "idle" "mid" || delta_failed=1
    fi
    
    if [ -f "$idle_img" ] && [ -f "$active_img" ]; then
        check_image_delta "$idle_img" "$active_img" "idle" "active" || delta_failed=1
    fi
    
    if [ "$delta_failed" -eq 1 ]; then
        echo "  ⚠️  Prop may not be visually responding to interaction"
    fi

    if [ "$SHOW_LATEST" = true ] && [ -f "$active_img" ]; then
        cp -f "$active_img" "$OUTPUT_DIR/latest.png"
        echo "  📸 Latest: $OUTPUT_DIR/latest.png"
    fi

    return $delta_failed
}

TOTAL_FAILURES=0

if [ -n "$TARGET_PROP" ]; then
    # Search for prop
    PROP_PATH=$(find "$PROP_DIR" -name "${TARGET_PROP}.tscn" 2>/dev/null | head -n 1)

    if [ -z "$PROP_PATH" ]; then
        echo "❌ Prop '$TARGET_PROP.tscn' not found in $PROP_DIR"
        echo "   Run './test_prop.sh --list' to see all props."
        exit 1
    fi
    
    run_validation "$TARGET_PROP" "$PROP_PATH"
    TOTAL_FAILURES=$?
    
else
    # No target specified — prompt for one or suggest --list
    echo "🎯 Prop Validator v2"
    echo ""
    echo "Usage:"
    echo "  ./test_prop.sh <PropName>        Full validation (screenshots + delta)"
    echo "  ./test_prop.sh <PropName> --quick Quick check (single screenshot)"
    echo "  ./test_prop.sh --list             List all props"
    echo "  ./test_prop.sh <PropName> --show  Copy screenshot to latest.png"
    echo ""
    echo "Examples:"
    echo "  ./test_prop.sh FireEmitter"
    echo "  ./test_prop.sh LeverV2 --quick"
    echo "  ./test_prop.sh --list"
    echo ""
    echo "Tip: use --quick when iterating on visuals. Use full mode for CI."
    exit 0
fi

# Summary
echo ""
if [ "$QUICK_MODE" != true ] && [ -n "$TARGET_PROP" ]; then
    if [ "$TOTAL_FAILURES" -gt 0 ]; then
        echo "⚠️  $TARGET_PROP had delta assertion failures."
    else
        echo "✅ $TARGET_PROP passed validation."
    fi
fi

if [ "$RETURN_BASE64" = true ] && [ -n "$TARGET_PROP" ]; then
    IMAGES=$(ls "$OUTPUT_DIR"/${TARGET_PROP}_*.png 2>/dev/null | sort)
    for img in $IMAGES; do
        NAME=$(basename "$img")
        echo "---BEGIN_BASE64_IMAGE:$NAME---"
        base64 -w 0 "$img" 2>/dev/null
        echo ""
        echo "---END_BASE64_IMAGE---"
    done
fi

echo "📁 Output: $OUTPUT_DIR"
exit $TOTAL_FAILURES
