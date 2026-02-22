#!/usr/bin/env bash
set -euo pipefail

# Generic A/B runner for OYS performance captures.
# Documentation: docs/performance/ab_benchmark.md
# It expects the OYS script to call:
#   CALL perf_capture_start "<tag>"
#   CALL perf_capture_stop "<tag>"
#
# By default it toggles shader warmup:
#   case A -> ODISEA_DISABLE_SHADER_WARMUP=0
#   case B -> ODISEA_DISABLE_SHADER_WARMUP=1

GODOT_BIN="${GODOT_BIN:-godot3-bin}"
OYS_SCRIPT="${OYS_SCRIPT:-res://core_v2/tests/perf/warmup_ab_base_terrace.oys}"
RUNS="${RUNS:-3}"
GODOT_FLAGS="${GODOT_FLAGS---no-window}"
QUIET_PERFMON="${QUIET_PERFMON:-1}"
CAPTURE_MARKER="${CAPTURE_MARKER:-[PerformanceMonitor][CAPTURE]}"

# A/B toggle config.
AB_TOGGLE_ENV="${AB_TOGGLE_ENV:-ODISEA_DISABLE_SHADER_WARMUP}"
CASE_A_LABEL="${CASE_A_LABEL:-warmup_on}"
CASE_A_VALUE="${CASE_A_VALUE:-0}"
CASE_B_LABEL="${CASE_B_LABEL:-warmup_off}"
CASE_B_VALUE="${CASE_B_VALUE:-1}"

# Keep tmp logs for inspection when debugging parser/runtime issues.
KEEP_LOGS="${KEEP_LOGS:-0}"

# Examples:
#   RUNS=5 ./scripts/run_warmup_ab.sh
#   GODOT_FLAGS="" RUNS=3 ./scripts/run_warmup_ab.sh   # with window/GPU
#   AB_TOGGLE_ENV=MY_FLAG CASE_A_LABEL=flag_off CASE_A_VALUE=0 CASE_B_LABEL=flag_on CASE_B_VALUE=1 ./scripts/run_warmup_ab.sh

print_help() {
    cat <<'EOF'
run_warmup_ab.sh - Generic OYS A/B performance benchmark runner

Usage:
  ./scripts/run_warmup_ab.sh [oys_script_path]

Environment:
  GODOT_BIN        Godot binary (default: godot3-bin)
  OYS_SCRIPT       OYS script path (default: warmup_ab_base_terrace.oys)
  RUNS             Runs per case (default: 3)
  GODOT_FLAGS      Extra Godot flags (default: --no-window)
                   Use GODOT_FLAGS="" for visible window.
  QUIET_PERFMON    Sets ODISEA_QUIET_PERFMON (default: 1)
  CAPTURE_MARKER   Log marker to parse JSON summary (default: [PerformanceMonitor][CAPTURE])

  AB_TOGGLE_ENV    Env var name to toggle across A/B (default: ODISEA_DISABLE_SHADER_WARMUP)
  CASE_A_LABEL     Label for case A (default: warmup_on)
  CASE_A_VALUE     Value for case A (default: 0)
  CASE_B_LABEL     Label for case B (default: warmup_off)
  CASE_B_VALUE     Value for case B (default: 1)
  KEEP_LOGS        Keep temp logs (1=yes, 0=no; default: 0)

Examples:
  RUNS=2 ./scripts/run_warmup_ab.sh
  GODOT_FLAGS="" RUNS=2 ./scripts/run_warmup_ab.sh
  AB_TOGGLE_ENV=MY_FEATURE CASE_A_LABEL=off CASE_A_VALUE=0 CASE_B_LABEL=on CASE_B_VALUE=1 ./scripts/run_warmup_ab.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_help
    exit 0
fi

if [[ "${1:-}" != "" ]]; then
    OYS_SCRIPT="$1"
fi

TMP_DIR="$(mktemp -d)"
if [[ "$KEEP_LOGS" == "1" ]]; then
    echo "Keeping logs in: $TMP_DIR"
else
    trap 'rm -rf "$TMP_DIR"' EXIT
fi

build_godot_cmd() {
    local -a cmd=("$GODOT_BIN")
    if [[ -n "$GODOT_FLAGS" ]]; then
        # Intentionally split flags, e.g. "--headless --no-window"
        # shellcheck disable=SC2206
        local extra_flags=( $GODOT_FLAGS )
        cmd+=("${extra_flags[@]}")
    fi
    printf '%s\n' "${cmd[@]}"
}

run_case() {
    local label="$1"
    local case_value="$2"
    local jsonl="$TMP_DIR/${label}.jsonl"

    : > "$jsonl"
    mapfile -t godot_cmd < <(build_godot_cmd)
    for i in $(seq 1 "$RUNS"); do
        local log_file="$TMP_DIR/${label}_${i}.log"
        echo "[${label}] run ${i}/${RUNS} ..."
        env \
            ODISEA_QUIET_PERFMON="$QUIET_PERFMON" \
            OYS_AUTO_RUN="$OYS_SCRIPT" \
            "$AB_TOGGLE_ENV=$case_value" \
            "${godot_cmd[@]}" >"$log_file" 2>&1

        local capture_line
        capture_line="$(grep -F "$CAPTURE_MARKER" "$log_file" | tail -n 1 || true)"
        if [[ "$capture_line" == "" ]]; then
            echo "No capture summary found for ${label} run ${i}."
            echo "See: $log_file"
            return 1
        fi
        local json_payload="${capture_line#*] }"
        echo "$json_payload" >> "$jsonl"
    done
}

summarize_case() {
    local label="$1"
    local jsonl="$TMP_DIR/${label}.jsonl"
    python3 - "$label" "$jsonl" <<'PY'
import json
import sys

label = sys.argv[1]
path = sys.argv[2]

rows = []
with open(path, "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        rows.append(json.loads(line))

if not rows:
    print(f"{label}: no data")
    sys.exit(0)

def avg(key):
    vals = [float(r.get(key, 0.0)) for r in rows]
    return sum(vals) / len(vals)

print(
    f"{label}: "
    f"avg_fps={avg('avg_fps'):.2f} "
    f"p1_fps={avg('p1_fps'):.2f} "
    f"p5_fps={avg('p5_fps'):.2f} "
    f"avg_process_ms={avg('avg_process_ms'):.3f} "
    f"p95_process_ms={avg('p95_process_ms'):.3f} "
    f"avg_draw_calls={avg('avg_draw_calls'):.1f} "
    f"frames_lt_50={avg('frames_lt_50'):.1f}"
)
PY
}

compare_cases() {
    local a_label="$1"
    local b_label="$2"
    local a_jsonl="$TMP_DIR/${a_label}.jsonl"
    local b_jsonl="$TMP_DIR/${b_label}.jsonl"
    python3 - "$a_label" "$a_jsonl" "$b_label" "$b_jsonl" <<'PY'
import json
import sys

a_label, a_path, b_label, b_path = sys.argv[1:5]

def load_rows(path):
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows

def avg(rows, key):
    vals = [float(r.get(key, 0.0)) for r in rows]
    return (sum(vals) / len(vals)) if vals else 0.0

a_rows = load_rows(a_path)
b_rows = load_rows(b_path)

a_fps = avg(a_rows, "avg_fps")
b_fps = avg(b_rows, "avg_fps")
a_p1 = avg(a_rows, "p1_fps")
b_p1 = avg(b_rows, "p1_fps")
a_p95 = avg(a_rows, "p95_process_ms")
b_p95 = avg(b_rows, "p95_process_ms")

delta_fps_pct = ((b_fps - a_fps) / a_fps * 100.0) if a_fps else 0.0
delta_p1_pct = ((b_p1 - a_p1) / a_p1 * 100.0) if a_p1 else 0.0
delta_p95_pct = ((b_p95 - a_p95) / a_p95 * 100.0) if a_p95 else 0.0

print(
    f"delta ({b_label} vs {a_label}): "
    f"avg_fps={delta_fps_pct:+.2f}% "
    f"p1_fps={delta_p1_pct:+.2f}% "
    f"p95_process_ms={delta_p95_pct:+.2f}%"
)
PY
}

echo "Running A/B benchmark with OYS script: $OYS_SCRIPT"
echo "Toggle: $AB_TOGGLE_ENV"
echo "Case A: $CASE_A_LABEL=$CASE_A_VALUE"
echo "Case B: $CASE_B_LABEL=$CASE_B_VALUE"
run_case "$CASE_A_LABEL" "$CASE_A_VALUE"
run_case "$CASE_B_LABEL" "$CASE_B_VALUE"

echo
summarize_case "$CASE_A_LABEL"
summarize_case "$CASE_B_LABEL"
compare_cases "$CASE_A_LABEL" "$CASE_B_LABEL"
