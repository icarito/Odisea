# A/B Performance Benchmark (OYS)

Infra:

- Runner: `scripts/run_warmup_ab.sh`
- Default OYS path: `core_v2/tests/perf/warmup_ab_base_terrace.oys`
- Capture API:
  - `CALL perf_capture_start "<tag>"`
  - `CALL perf_capture_stop "<tag>"`

## Quick Start

Headless:

```bash
RUNS=1 ./scripts/run_warmup_ab.sh
```

Window (GPU path):

```bash
GODOT_FLAGS="" RUNS=1 ./scripts/run_warmup_ab.sh
```

Window + uncapped:

```bash
vblank_mode=0 GODOT_FLAGS="--windowed --resolution 640x360" RUNS=1 ./scripts/run_warmup_ab.sh
```

## Generic Feature Toggle

Any env flag can be tested with the same runner:

```bash
AB_TOGGLE_ENV=MY_FEATURE_FLAG \
CASE_A_LABEL=feature_off CASE_A_VALUE=0 \
CASE_B_LABEL=feature_on CASE_B_VALUE=1 \
RUNS=1 \
./scripts/run_warmup_ab.sh
```

Example for box hibernation:

```bash
AB_TOGGLE_ENV=ODISEA_PUSHBOX_HIBERNATION \
CASE_A_LABEL=hibernation_off CASE_A_VALUE=0 \
CASE_B_LABEL=hibernation_on CASE_B_VALUE=1 \
vblank_mode=0 GODOT_FLAGS="--windowed --resolution 640x360" RUNS=1 \
./scripts/run_warmup_ab.sh
```

## Output Metrics

- `avg_fps`, `p1_fps`, `p5_fps`
- `avg_process_ms`, `p95_process_ms`
- `frames_lt_50`
- delta line: `delta (B vs A)`

Interpretation:

- Higher `avg_fps` and `p1_fps` is better.
- Lower `p95_process_ms` and `frames_lt_50` is better.

## Notes

- The benchmark OYS script intentionally has no debug `PRINT` lines.
- The capture marker `[PerformanceMonitor][CAPTURE]` is kept for parser compatibility.
