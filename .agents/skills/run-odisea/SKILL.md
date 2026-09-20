---
name: run-odisea
description: Build, run, and drive Odisea game. Use when asked to start Odisea, run its tests, build it, take a screenshot, validate a prop, validate UI, eval/run GDScript headlessly, or interact with the running game. Covers eval.sh direct-invocation, test_prop.sh, test_ui.sh, runtest.sh, OYS tests, GdUnit3, ANNA MCP bridge, and bridge telemetry HTTP.
---

Odisea is a 3D Godot 3.6 platformer game. Three ways to drive it, ordered by what
works from a clean/headless checkout:

Shared canonical agent reference: `docs/agents/tooling.md`. This skill keeps
Codex-native operational details and historical ANNA notes.

1. **Direct invocation** — `.Codex/skills/run-odisea/eval.sh` runs GDScript inside a
   real headless SceneTree so you can import-and-call internal code (generators,
   rotators, parsers) and print results. **Fastest path, and the layer most PRs here
   touch** — this codebase is mostly internal systems. Needs only the Box3D fork, via `tools/godot`.
2. **Headless validation harnesses** — `test_prop.sh` (prop screenshots), `test_ui.sh`
   (UI screenshots), `runtest.sh` (OYS determinism + GdUnit3 suites). Deterministic, no
   live game needed, produce PNGs / pass-fail.
3. **ANNA MCP bridge** (`odisea-mcp`) + **bridge telemetry HTTP** — real-time inspection
   of a *running* game. The MCP path needs the game open with `ANNA_ENABLED=1`
   (Sebastian's editor sets this) and is **not available from a clean headless
   container**. The HTTP telemetry path (FD-162, below) works whenever a game is
   connected to the bridge and needs no MCP.

All paths below are relative to the repo root (`src/`). The driver lives at
`.Codex/skills/run-odisea/eval.sh`.

## Prerequisites

```bash
# Always the Box3D fork: tools/godot runs what tools/godot_bin.sh resolves (and rebuilds).
# NEVER godot3-bin: stock 3.6.2, no Box3D, cannot export Android, strips project.godot settings.
tools/godot --version   # expect: 3.6.4.rc.custom_build...
```

No additional apt packages are needed — Godot ships its own renderer (Mesa OpenGL ES 2.0 works on Linux).

## Direct invocation — eval GDScript headlessly (agent path, start here)

`.Codex/skills/run-odisea/eval.sh` runs GDScript inside a real headless `SceneTree`
(no window, audio muted) so you can import-and-call internal project code and print
results. This is the fastest way to exercise the systems most PRs here touch
(generators, rotators, parsers, scene loads) without booting the full game.

```bash
# inline body — wrapped in SceneTree._init(), quit() added for you, load() resolves res://
.Codex/skills/run-odisea/eval.sh 'print("[t] threads=", OS.has_feature("threads"))'
# -> [t] threads=False
```

```bash
# import-and-call internal logic (multi-line; tag your prints, output is filtered clean)
.Codex/skills/run-odisea/eval.sh 'var m=load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
m.apply_params({"grid_width":8,"grid_depth":12})
print("[t] MST cells=", m.generate_grid_data(7).size())'
# -> [t] MST cells=96
```

```bash
# load a scene to confirm it instances (e.g. after editing a .tscn)
.Codex/skills/run-odisea/eval.sh 'var inst=load("res://core_v2/levels/interiors/Dome_Crio.tscn").instance()
print("[t] Dome_Crio children=", inst.get_child_count())'
# -> [t] Dome_Crio children=19
```

```bash
# file mode: a standalone script that `extends SceneTree` (copied into the project if external)
.Codex/skills/run-odisea/eval.sh -f /tmp/my_check.gd
```

Knobs: `EVAL_RAW=1` shows unfiltered Godot output (boot lines, leak-at-exit noise);
`EVAL_TIMEOUT=<s>` (default 90); `GODOT_BIN` overrides the binary. The driver tags its
own temp files `_eval_*.gd` and removes them.

The inline body runs **inside `_init()`**, so statements only: use `var`, not
`const`/`enum`/`func` (those must be at script scope — use `-f script.gd` for those).
Tag your prints (`print("[t] ...")`) so they stand out from any residual engine noise.

This is also how to **syntax-check** a script without an editor:

```bash
tools/godot --no-window --check-only -s core_v2/systems/WorldRotator.gd 2>&1 | grep -i "parse error"
# (no output = clean; a "DomeRegistry isn't declared" line is a harmless autoload-not-loaded artifact in isolation)
```

## ANNA MCP Bridge — Interact with the Running Game (live-game path)

The MCP server is configured in `.Codex/settings.json` as `odisea-mcp`. It proxies to the
ANNA TCP bridge running inside the game on `127.0.0.1:5000`.

### Golden rule: always start with bridge_status

```
bridge_status
```

- `process_launched_by_mcp: false` + no connection → game is not running, or was launched by Sebastian manually
- If the game is open in the Godot editor → use `bridge_connect` (never `bridge_launch` when a game is already open)
- Only use `bridge_launch` when there is truly no running Godot process

### Connect to Sebastian's running game

```
bridge_connect {"host": "127.0.0.1", "port": 5000}
```

### Launch a headless game (when no Godot process is running)

```
bridge_launch {
  "project_path": ".",
  "godot_exe": "tools/godot",
  "headless": false
}
```

### Inspect, modify, screenshot

```
inspect_node {"node_path": "/root/Pilot"}
inspect_node {"node_path": "/root/Main", "include_children": true, "max_depth": 2}

set_property {"node_path": "/root/Main/WorldEnvironment", "property": "environment.glow_enabled", "value": true}

capture_vision {"include_base64": true}

execute_oys {"script_command": "SPAWN res://core_v2/props/CircuitCable.tscn"}
```

### Resources (read-only runtime snapshots)

- `odisea://scene/hierarchy` — SceneTree JSON (name/type/path)
- `odisea://simulation/telemetry` — player position, velocity, active OYS line, FPS
- `odisea://olcs/logic-state` — Levers/Doors/Gates logical values

### Stop (only if YOU launched the game with bridge_launch)

```
bridge_stop
```

**Never call `bridge_stop` if Sebastian opened the game manually.**

## Push an ad hoc scene to a running game (PCK injection, Anbernic/device path)

Build a scene locally, pack it, upload it to a running game on a remote device, and have it
load the scene — no full re-export, no reinstall. This is the iteration loop for the Anbernic
(FD-299): edit `.tscn` → push → measure, in seconds.

### Quick start (turnkey, cualquier agente)

```bash
export PORTMASTER_HOST=root@192.168.18.36   # opcional; default root@angel.local (mDNS puede tardar)

# 1) Deja el RG351V listo: peer local + engine DEBUG + dev.sh con el bridge + reinicio.
tools/push_scene_pck.sh --setup

# 2) Empuja la escena y entrá por el flujo normal (spawn del Pilot / SceneManager):
tools/push_scene_pck.sh res://core_v2/levels/RingHub_Level.tscn --no-launch
curl -s --get --data-urlencode \
  "expr=get_node('/root/SceneManager').goto_scene('res://core_v2/levels/RingHub_Level.tscn')" \
  "$ANNA_PEER_URL/eval"
```

`--setup` es idempotente: si ya hay un juego debug conectado, solo reescribe `dev.sh` y no
reinicia. Cuando termines, devolvé el equipo al arranque normal:

```bash
tools/push_scene_pck.sh --restore
```

**Iterar la MISMA escena sin reiniciar:** Godot cachea por `res://` path; re-subir la misma
ruta hace que el juego siga viendo la versión vieja. Para eso está `--unique`: expone la
escena bajo `res://.dev_push/<id>.tscn` y hay que entrar a la ruta que imprime.

```bash
tools/push_scene_pck.sh res://core_v2/levels/RingHub_Level.tscn --no-launch --unique
# -> entrar a res://.dev_push/RingHub_Level_<ts>.tscn (lo imprime el comando)
```

Sin `--no-launch`, `reload_pck` hace un `change_scene` crudo (sin spawn); sirve para escenas
que ya traen su `Pilot` incrustado, como `RingHub_Level`.

```bash
# extras: pack additional res:// files the scene needs and that are NOT in the main pack
tools/push_scene_pck.sh res://core_v2/tests/ladder/DomeDefaultV2Test.tscn \
  res://core_v2/levels/interiors/DomeTerraceV2_baked.mesh \
  res://core_v2/levels/interiors/DomeTerraceV2_baked.shape --id dome_v2_test
# --id sets the artifact name (default: scene basename + timestamp); --no-launch skips scene change
```

How it works: PCKPacker (fork editor, headless) packs the listed files → scp to
`$PORTMASTER_DIR/conf/godot/app_userdata/Odisea/updates/packages/<id>.pck` plus a
`<id>.json` sidecar with the sha256 (ANNAV2's dev override path for `reload_pck`) →
POST `reload_pck {artifact_id, scene}` to the local peer → the game loads the pack and
switches scene. Dependencies already in the main pack resolve by themselves; only pack
what's new. A failed `change_scene` can wedge the game: `tools/push_scene_pck.sh --setup`
(reboot) before retrying.

Device prerequisites (las resuelve `--setup`):
- `PORTMASTER_HOST` (default `root@angel.local`; si mDNS tarda usá la IP, ej. `root@192.168.18.36`).
- El port corre el **binario debug** via `dev.sh` (exporta `ANNA_V2_BRIDGE=<ip_escritorio>:4999`
  y pone `ENGINE` en `odisea.frt.debug.aarch64`, bajado del release pinneado del fork) para que
  el peer acepte comandos. `--setup` lo baja, lo instala y escribe `dev.sh`.
- Peer local del escritorio: `tools/ensure_peer.sh` (lo arranca `--setup`).

Scene-change gotchas:
- `reload_pck` uses raw `change_scene` (no spawn flow, no player). Prefer pushing with
  `--no-launch` and then driving `SceneManager.goto_scene('<res://path>')` via the peer's
  `/eval` so the normal spawn flow runs (SceneManager instances the Pilot at SpawnPointV2).
- Spawn check: heartbeat `position` stuck at `[0,0,0]` + `dc 0` = no player camera. Fix:
  `get_node('/root/SceneManager')._ensure_player_in_current_scene(get_tree().current_scene)`.
- Mute the device for headless test runs: `AudioServer.set_bus_mute(0, true)`.

Measure (Anbernic): `tools/anbernic_probe.sh <etiqueta> [segundos] [shots]` — fault count
(kernel-timestamp window), GPU pages, MemAvailable, central heartbeat, and a **grim series**
(`shots>1`); `ANNA_MOVE=1` rotates Elías' yaw between shots so each shot is fresh content.
One full frame can lie (a single completed frame then failure) — coverage must be judged
on the series.

## Comunicar resultados visuales

- Después de `capture_vision {"include_base64": true}` → mostrar la imagen inline en el chat inmediatamente.
- Después de `test_prop.sh` o `test_ui.sh` → leer el PNG con el Read tool y mostrarlo inline. VS Code renderiza PNGs.
- **No uses la screenshot para deducir posiciones/propiedades** — para eso está `inspect_node`.
- Cuando corresponda, reportar ambos: "Elías está en (x, y, z) [de inspect_node] y así se ve la escena: [img]"

## Cuándo usar ANNA vs capture_vision

- **`inspect_node`** → medir posiciones, distancias, propiedades de nodos, contar hijos, leer valores numéricos. Es la fuente de verdad para datos cuantitativos.
- **`capture_vision`** → evaluar gaps visuales, artefactos gráficos, alineación de geometría, calidad visual. Solo para cosas que requieren visión.
- **Regla**: usar `inspect_node` primero para ubicar nodos y medir; `capture_vision` solo si la pregunta es inherentemente visual (¿se ve bien?, ¿hay un gap visible?, ¿coinciden los bordes?).

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

## Local test selection (agent path)

Run only the GdUnit, OYS, or Python test(s) directly affected by the change. Do not run the full suite locally unless the task explicitly requires it. Use pytest headlessly by default:

```bash
./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_<relevant>_gd
./.venv/bin/pytest tests/test_<module>.py
```

Discover a GdUnit/OYS pytest node first when needed:

```bash
./.venv/bin/pytest tests/test_odisea_runner.py --collect-only -q -k <relevant>
./runtest.sh --list          # suites GdUnit, OYS cases, how to discover pytest nodes
```

**Backend contract — Server headless, same as CI.** `runtest.sh` selects the fork's pinned
`platform=server` binary and passes `--headless --no-window`, even with `DISPLAY`. Those flags
do not turn Godot 3's X11 editor into Server. CI uses that pinned binary; an X11-hidden run does **not**
validate CI: the window/input driver changes and VirtualMouse and Box3D can differ (asserts
that pass locally and fail in CI, or vice versa). `--show` is the only graphical path and is
for looking, not validating. `tests/test_runtest_runner_contract.py` runs in CI and catches a
reintroduced display branch.

CI parity, all overridable by env:

- `ANNA_V2_NO_CENTRAL=1` and `ODISEA_TEST_TIMEOUT_SEC=180` are the local defaults (same as CI).
- `./runtest.sh --ci` reproduces the core CI job exactly: one gdunit process over the whole
  suite, no determinism, preflight already done, 420s wall timeout. Use it to reproduce a CI
  failure; the local default (pytest delegate, one Godot per suite) changes the order and the
  accumulated orphan state.
- `./runtest.sh --filter <substring>` runs matching pytest nodes (forces the delegate).

## Run All GdUnit3 Tests (CI only)

```bash
./runtest.sh --ci        # reproduccion fiel del job core de CI
./runtest.sh -a ./core_v2/tests/
```

Do not use the full suite locally as a default; use a selected pytest node instead. If you
must reproduce a CI failure, use `--ci`, not the plain full-suite invocation.

## ANNA V2 Telemetry Capture (local, bridge-independent)

ANNA V2 ([core_v2/anna/v2/ANNAV2.gd](../../../core_v2/anna/v2/ANNAV2.gd)) is the `ANNAV2`
autoload — a WebSocket telemetry/bridge separate from V1 (`AnnaInterface`, the RL TCP
bridge). It collects player telemetry (position, velocity, yaw/pitch/roll, fps, mem, scene)
every frame and streams it to a peer on port 4999. It **never crashes** if the peer is absent.

V2 also has a **local capture path** that needs no Python bridge — it buffers frames in a
ring buffer and exports them to JSON. Use this for headless debugging/analysis.

### Drive it from OYS

- `ANNA_ENABLE` — starts V2 capture (also toggles the V1 RL agent if one is attached).
- `ANNA_DISABLE` — stops V2 capture.
- `ANNA_DUMP path=user://foo.json` — writes captured frames to JSON (omit `path=` to use the
  configured/default path). Logic command; consumes no frame time.

Example test: [core_v2/tests/test_anna_v2_telemetry.oys](../../../core_v2/tests/test_anna_v2_telemetry.oys).
Mark telemetry tests with `// OYS_NODET=1` — they're not movement-determinism tests, and
`WALK` has ~0.0125m drift that trips the 0.01 replay threshold.

```bash
./runtest.sh --oys test_anna_v2_telemetry
# dump lands at ~/.local/share/godot/app_userdata/Odisea/anna_v2_test_telemetry.json
```

### Drive it from controllers / autoload

`ANNAV2` is a global autoload, so any script can call:

```gdscript
ANNAV2.set_capture_enabled(true)
ANNAV2.register_telemetry_point("jump_count", jumps)  # merged into every frame
ANNAV2.dump_telemetry_json("user://run.json")
var frames = ANNAV2.get_capture_log()                 # Array of frame dicts
```

### Live telemetry via the Bridge Peer (FD-162)

Per [FD-162](../../../docs/features/FD-162-odisea-bridge.md), **ANNA MCP (V1, port 5000) is
deprecated** for telemetry. ANNA V2 instead streams heartbeats over WebSocket to a local
**peer node** ([odisea_peer.py](../../../odisea_peer.py)) on port 4999, which serves the live
data over plain HTTP. Query it with WebFetch — no MCP needed:

- `http://localhost:4999/status` — latest heartbeat for every connected Godot (full `player.{...}`)
- `http://localhost:4999/status?player_id=<id>` — one player
- `http://localhost:4999/sessions` — active session ids
- `http://localhost:4999/peers` — connected player ids
- `http://localhost:4999/health` — `{ok, players_known, central_connected}`

Sebastian launches the peer from VS Code: **Run Task → "Run Odisea Bridge Peer"** (or
`python3 odisea_peer.py`). First-time setup: **"Install Bridge Peer deps"** task, or
`python3 -m pip install -r requirements-bridge.txt` (aiohttp + zeroconf). Godot discovers the
peer by mDNS (`_odisea._tcp`) and connects automatically; ANNA V2 retries every 2s and never
crashes if the peer is down. `odisea_central.py` (:5003, token-gated) aggregates peers — not
needed for local debugging.

### Env gating (headless auto-capture)

- `ANNA_V2_CAPTURE=1` — auto-enable capture at boot.
- `ANNA_V2_CAPTURE_DUMP=user://x.json` — auto-dump to this path on shutdown (`_exit_tree`).
- `ANNA_V2_CAPTURE_MAX=N` — ring-buffer frame cap (default 36000 ≈ 10 min @ 60fps).
- `ANNA_V2_BRIDGE=host:port` / `ANNA_V2_SERVER_ENABLED=1` — point at / host the WebSocket peer.

JSON shape: `{player_id, session_id, game_version, godot_version, captured_at, frame_count,
frames:[{position, velocity, yaw, pitch, roll, mode, scene, zone, tick, fps, memory_mb,
t_msec, ...custom points}]}`.

## Run (human path)

Open the project in Godot Editor 3.6.x and press F5. Main scene: `res://core_v2/bootstrap/Boot.tscn`.

## Test

```bash
./runtest.sh --oys test_salto_vertical   # single fast OYS test (~80s)
./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_<relevant>_gd
```

Expected: OYS tests print `PASSED` and exit 0. Full suite prints `✅ Todos los tests pasaron`.

---

## Gotchas

- **`bridge_status` doesn't tell you if you're connected** — it returns config state (host/port/process info), not a TCP-connected flag. If `process_launched_by_mcp` is false and the game is open, call `bridge_connect` and see if it succeeds.
- **Never call `bridge_launch` when Godot is already open** — it would spawn a second process. Always `bridge_status` first; if there's any Godot process visible, use `bridge_connect`.
- **Never call `bridge_stop` if Sebastian opened the game** — only stop a game you launched with `bridge_launch`.
- **ANNA requires `ANNA_ENABLED=1`** — the Godot editor sets this automatically when opened. Headless launches via `bridge_launch` also set it. If you're connecting to a manually launched game binary without the editor, ensure the env var is set.
- **`--runner` flag is not valid for GdUnit3** — `runtest.sh --oys` routes internally through GdUnit3's `GdUnitCmdTool.gd`. The `--runner` flag only applies to the outer pytest wrapper for full-suite runs, not `--oys` runs.
- **Delta assertions may warn but not fail** — `test_prop.sh` uses a 2% pixel-delta threshold. If a prop has subtle animation, you may see "DELTA ASSERTION FAILED" even when screenshots are visually different. The exit code is the final authority.
- **`ERROR: NO GRAB`** — This is harmless; it appears when Godot runs headless (`--no-window`) and tries to grab mouse focus. All tests pass despite it.
- **Never run tests with X11 hidden (`--no-window` only)** — it is not CI parity. `runtest.sh` and `eval.sh` force the Server driver (`--headless --no-window`); keep it that way. A display-dependent backend makes VirtualMouse/Box3D asserts diverge from CI. `tests/test_runtest_runner_contract.py` guards this.
- **Audio is muted automatically** — `ODISEA_FORCE_MUTE_AUDIO=1` is set in all test scripts to silence audio in headless mode.
- **OYS test replay takes ~80s** — Each `--oys` test runs two phases: record + replay. This is normal.
- **`run/main_scene`** in `project.godot` is `res://core_v2/bootstrap/Boot.tscn`, not the Menu scene listed in some older docs.
- **Editing a `.gd` does NOT update a web/HTML5 build until you re-export the `.pck`** — GDScript is packed into `index.pck`. The "Run in Browser" editor button exports a temp `.pck` to a system dir (not `build/`), and browsers cache it aggressively. To confirm the loaded `.pck` has your code: `grep -a "<a-string-from-your-edit>" build/index.pck` (absent = stale export). Hard-reload (Ctrl+Shift+R) after re-exporting.
- **The container's `tools/godot` reports `OS.has_feature("threads") == False`** — same as a non-threads HTML5 export. Code gated on threads (e.g. `ScaffoldWFCThreaded`) takes its no-thread fallback both here and in the non-threads web build. Useful: you can reproduce no-thread behaviour headlessly.
- **`--check-only` against a script that uses an autoload class in isolation** prints e.g. `DomeRegistry isn't declared in the current scope` — that's the autoload not being loaded for a bare check, not a real error. Filter those; a true parse error says `Parse Error:` / `parse error`.
- **`tools/godot --no-window` leaks ObjectDB/Resources at exit** when a script instances a scene without freeing it (`instances leaked at exit`, `_first != nullptr`). Harmless for one-shot eval scripts; `eval.sh` filters it.
- **Headless GUI export/reimport via `--editor --quit` is unreliable** — it often closes before reimporting changed `.import` files. To force a texture reimport, delete the cached `.import/<name>-*.stex` and let the editor regenerate, or reimport from the open editor; verify with `ls .import/<name>-*.stex`.

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
- **CSG subtract (`operation = 2`) pierces through**: if the subtracted child's height ≥ half the parent, it cuts all the way through and shows the white PropStage backdrop. Use additive geometry (pads on top) for surface detail instead
- **`SlidingObjectV2` hides `MeshInstance` when custom siblings exist**: name the base box exactly `MeshInstance`; extra `CSGBox` siblings (which are `Spatial`, not `MeshInstance`) are safe and won't trigger the hide logic
- **Highly metallic surfaces look black in PropStage**: `metallic=1.0, roughness<0.25` reflects almost nothing under the low PropStage ambient. Correct in-game. Don't raise roughness to compensate the test view

## Troubleshooting

- **`bridge_connect` times out**: The game is not running, or ANNA_ENABLED=1 was not set. Start the game from the Godot editor (which sets the env var automatically) then retry.
- **`bridge_launch` fails with port already in use**: Another Godot is already running. Use `bridge_connect` instead.
- **`Unknown '--runner' command!` / `Abnormal exit with 100`**: You passed `--runner gdunit` to `runtest.sh --oys`. Remove `--runner`; OYS tests don't accept it.
- **`No screenshots found for <PropName>`**: Prop path not found. Check spelling; prop must be a `.tscn` in `core_v2/props/`.
- **`SCRIPT ERROR:` in log**: A GDScript error occurred — the log file has details. Run with `--debug` flag for full output: `./runtest.sh --debug --oys <name>`.
- **`No test suites found`**: GdUnit3 path argument is wrong. Use `./core_v2/tests/` (with trailing slash).
