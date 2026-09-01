# FD-287: Reusable light flicker component (parpadeo determinista)

**Status:** Planned
**Priority:** Medium
**Effort:** Small
**Created:** 2026-09-01
**Completed:** -

## Problem

Several lighting situations need a light that flickers or fails without re-authoring each
prop: fluorescent "starter" stutter on power-on, a light failing during the final storm, a
light dropping out on low power. Today this exists only inside `FluorescentLight.gd`
(`flicker_enabled` / `flicker_speed` / `flicker_intensity`), so any other fixture
(`SciFiStaticLightV2`, `SciFiHangingLightV2`, sconces, studs) can't use it.

FD-284 (dome light states) explicitly requires a "flicker / failing lights" emissive layer
on top of the current state — never a re-bake. This component delivers that layer as a
reusable, deterministic, GLES2-safe node.

Goal: attach one node to any light prop and it flickers, without touching the prop's logic,
without new transparency, and with replay-deterministic output.

## Solution

### `LightFlicker` — reusable deterministic flicker component

- New `core_v2/components/LightFlicker.gd` (Node, not a prop).
- Exports:
  - `export(NodePath) var target_path` — the light prop (or any node exposing the methods
    below) whose emissive/energy will be modulated.
  - `export(float) var base_intensity := 1.0` — multiplier applied when "on".
  - `export(float, 0.0, 1.0) var on_ratio := 0.85` — fraction of each cycle the light reads
    as lit (a failing light dips to ~0.5; a healthy stutter stays ~0.9).
  - `export(float, 0.1, 30.0) var period := 0.9` — full flicker cycle in seconds.
  - `export(int) var seed := 0` — RNG seed so the flicker sequence is reproducible.
  - `export(bool) var only_when_active := true` — flicker only modulates while the target
    reads active; otherwise the component is inert (idle culling).
- Modulates, in order of preference, whichever the target exposes:
  1. `set_flicker_multiplier(f: float)` if present (contract for props that opt in).
  2. Else scale the target's `light_energy` / `emission_energy` by writing a multiplier via
     cached base values (read `light_energy`/`emission_energy` once at `_ready`, then write
     `base * factor` each tick).
  3. Else `visible = (factor > threshold)` for plain `Light`/`MeshInstance` targets.
- Determinism: use a local `RandomNumberGenerator` seeded from `seed` (do NOT use the global
  RNG). Advance the pattern from a monotonic time accumulator so the same seed + elapsed
  time reproduces the same factor. Belongs to `replay_sync`; `get_snapshot()` /
  `restore_snapshot()` store/restore `seed` and the time accumulator.
- Pattern: a two-state (on/off) markov-ish blink is enough — no audio, no particles. The
  factor is `1.0` while in the "on" portion of the cycle and a low value (derived from
  `on_ratio`) during the "off" portion, with optional short sub-blinks during a "stutter"
  startup window. Keep it visually legible, not stroboscopic (period ≥ 0.4s recommended,
  no hard strobe above ~3 Hz sustained).
- Performance: when `only_when_active` and the target is inactive, set
  `set_process(false)` and restore base values once; re-enable on activation.

### Contract note (optional prop hook)

- Add an opt-in `set_flicker_multiplier(f)` (and `get_flicker_base()`) to at most
  `FluorescentLight.gd` if it helps unify, but do NOT rewrite its existing flicker logic —
  leave current behavior intact. The component must work against the generic
  energy/emission/visible fallbacks so it needs no prop changes.

## Constraints

- Godot 3.x / GDScript 1.x: `yield` with strings, classic `connect()`, no `@onready`, no
  Godot 4 syntax.
- GLES2: emissive/energy modulation only. No new transparency, no post-processing, no
  lightmap re-bake.
- Deterministic: seeded local RNG, snapshot-able accumulator, `replay_sync` group.
- Composition over inheritance; signals, never `get_parent()` chains.
- Static typing in production code.
- Do not modify `LogicCircuitManager`, `InteractableBaseV2`, or `MobileLightBudget`.

## Files to Modify

- `core_v2/components/LightFlicker.gd` (new)
- `core_v2/tests/test_light_flicker.gd` (new)
- `docs/features/FD-287_light_flicker.md` (this file)

## Verification

1. `./runtest.sh -a ./core_v2/tests/test_light_flicker.gd` — same seed reproduces the same
   factor sequence; different seeds differ; snapshot/restore round-trips the accumulator;
   `only_when_active` culls processing when inactive.
2. `godot3 --headless --quit` in project root — no script errors on load.
3. `./test_prop.sh SciFiStaticLightV2 --editor-path=$(which godot3)` with a `LightFlicker`
   attached — screenshot delta confirms the light visibly flickers (idle vs active frames
   differ beyond the base toggle).
