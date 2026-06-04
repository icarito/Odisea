---
name: run-odisea
description: Build, run, and drive Odisea game. Use when asked to start Odisea, run its tests, build it, take a screenshot, validate a prop, validate UI, or interact with the running game. Covers test_prop.sh, test_ui.sh, runtest.sh, OYS tests, and GdUnit3.
---

Odisea is a 3D Godot 3.6 platformer game. It has no interactive driver — instead it exposes
three scriptable validation harnesses that agents use to observe behavior:

- **`./test_prop.sh`** — validate a prop scene visually (screenshots + pixel delta checks)
- **`./test_ui.sh`** — validate a UI scene visually
- **`./runtest.sh`** — run GdUnit3 / OYS determinism tests headlessly

All paths below are relative to the repo root (`src/`).

## Prerequisites

```bash
# Godot 3.6.x must be on PATH as godot3-bin
which godot3-bin   # verify
godot3-bin --version   # expect: 3.6.x.stable
```

No additional apt packages are needed — Godot ships its own renderer (Mesa OpenGL ES 2.0 works on Linux).

## Validate a Prop (agent path)

Run `test_prop.sh` to capture screenshots of a prop in all animation states:

```bash
./test_prop.sh <PropName>
```

Add `--base64` to get PNG data on stdout (for agent inspection):

```bash
./test_prop.sh <PropName> --base64
```

Screenshots land in `test_output/props/<PropName>_0_idle.png`, `_1_mid.png`, `_2_active.png`, `_3_off.png`.

Example — CircuitCable prop validation:

```bash
./test_prop.sh CircuitCable
# ✅ Success: 4 screenshots generated for CircuitCable
```

## Validate UI (agent path)

```bash
./test_ui.sh --scene=<SceneName> --base64
```

Screenshots land in `test_output/ui/<scene_name>_*.png`.

Example:

```bash
./test_ui.sh --scene=DebugOverlay
# ✅ Success: 1 UI screenshots generated
```

## Run OYS Determinism Test (agent path)

OYS tests are replay-determinism tests. Run a single test by name:

```bash
./runtest.sh --oys <test_name>
```

The test name is the file basename without `.oys` extension. Available tests:

```bash
ls core_v2/tests/*.oys | sed 's|core_v2/tests/||; s|\.oys||'
```

Example:

```bash
./runtest.sh --oys test_salto_vertical
# ✅ Test OYS 'test_salto_vertical' pasó
```

Full test log is saved to `reports/gdunit_<timestamp>.log`. If terminal output is filtered, read:

```bash
cat reports/gdunit_runner.log | tail -100
```

## Run All GdUnit3 Tests (agent path)

```bash
./runtest.sh -a ./core_v2/tests/
```

This uses the pytest delegate (parallel, 3 workers) when available, or falls back to GdUnit3 directly.

## Run (human path)

Open the project in Godot Editor 3.6.x and press F5. Main scene: `res://core_v2/bootstrap/Boot.tscn`.

## Test

```bash
./runtest.sh --oys test_salto_vertical   # single fast OYS test (~80s)
./runtest.sh -a ./core_v2/tests/         # full suite (long)
```

Expected: OYS tests print `PASSED` and exit 0. Full suite prints `✅ Todos los tests pasaron`.

---

## Gotchas

- **`--runner` flag is not valid for GdUnit3** — `runtest.sh --oys` routes internally through GdUnit3's `GdUnitCmdTool.gd`. The `--runner` flag only applies to the outer pytest wrapper for full-suite runs, not `--oys` runs.
- **Delta assertions may warn but not fail** — `test_prop.sh` uses a 2% pixel-delta threshold. If a prop has subtle animation, you may see "DELTA ASSERTION FAILED" even when screenshots are visually different. The exit code is the final authority.
- **`ERROR: NO GRAB`** — This is harmless; it appears when Godot runs headless (`--no-window`) and tries to grab mouse focus. All tests pass despite it.
- **Audio is muted automatically** — `ODISEA_FORCE_MUTE_AUDIO=1` is set in all test scripts to silence audio in headless mode.
- **OYS test replay takes ~80s** — Each `--oys` test runs two phases: record + replay. This is normal.
- **`run/main_scene`** in `project.godot` is `res://core_v2/bootstrap/Boot.tscn`, not the Menu scene listed in some older docs.

## Prop design iteration loop

To collaboratively improve a prop's visual design, the standard loop is:

1. Inspect screenshots — read them from `test_output/props/` with the Read tool
2. Read the `.tscn` to understand current geometry and materials
3. Edit the `.tscn` (materials inline as `[sub_resource]`, CSG nodes for geometry)
4. Re-run `./test_prop.sh <PropName>` and read the new screenshots
5. Repeat until satisfied, then commit

Key geometry facts for props built with CSG:
- Materials go inline as `[sub_resource type="SpatialMaterial"]` in the `.tscn` — no separate `.tres` needed for prototype work
- `SlidingObjectV2` reads `size` and `slide_vector`; `slide_vector` must exceed `size.x` (or relevant axis) to fully clear the opening without clipping
- `RotatingObjectV2` `rotation_amount = 360.0` gives a full spin (good for valves)
- The PropStage camera angle is oblique/low — horizontal details (spokes, surface markings) may not be visible in screenshots but will be from the in-game top-down-ish perspective
- `FloorHatchProxy.gd` exposes `hatch_size` to resize the door and hole together from the Inspector

## Troubleshooting

- **`Unknown '--runner' command!` / `Abnormal exit with 100`**: You passed `--runner gdunit` to `runtest.sh --oys`. Remove `--runner`; OYS tests don't accept it.
- **`No screenshots found for <PropName>`**: Prop path not found. Check spelling; prop must be a `.tscn` in `core_v2/props/`.
- **`SCRIPT ERROR:` in log**: A GDScript error occurred — the log file has details. Run with `--debug` flag for full output: `./runtest.sh --debug --oys <name>`.
- **`No test suites found`**: GdUnit3 path argument is wrong. Use `./core_v2/tests/` (with trailing slash).
