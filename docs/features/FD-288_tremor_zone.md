# FD-288: Tremor zone (temblor ambiental con impulso físico determinista)

**Status:** Planned
**Priority:** Medium
**Effort:** Small
**Created:** 2026-09-01
**Completed:** -

## Problem

The ship can shake the camera (`CinematicManager.trigger_camera_shake`, OYS
`CAMERA_SHAKE`) and can push bodies with continuous wind (`WindTunnelV2`), but there is
no **tremor**: a short, oscillatory physical shake that rattles the player and nearby
rigid props (pushable boxes, loose debris) — the "whole deck lurches" feeling for the
final storm, a reactor pulse, or a decompression thump.

Goal: a reusable, deterministic tremor component that (a) applies oscillatory impulses to
the player and to `RigidBody`/`PushableBoxV2`, and (b) can be triggered globally for
ship-wide events, reusing the existing camera shake for visual feedback.

## Solution

### A. `TremorZoneV2` — localized tremor component

- New `core_v2/components/TremorZoneV2.gd` (Area, mirroring `WindTunnelV2`).
- Exports:
  - `export(float) var impulse_strength := 6.0` — magnitude of each physics impulse.
  - `export(float, 0.05, 5.0) var period := 0.12` — seconds per oscillation half-cycle.
  - `export(float, 0.5, 20.0) var frequency := 10.0` — shake frequency for the camera
    feedback (passed through to `CinematicManager.trigger_camera_shake`).
  - `export(float) var duration := 1.0` — total tremor length; 0 or negative = infinite
    while `is_active`.
  - `export(int) var seed := 0` — seed for the shake direction sequence.
  - `export(bool) var affect_player := true`
  - `export(bool) var affect_rigid := true`
  - `export(float) var camera_amplitude := 0.05` — 0 disables camera feedback.
  - `export(bool) var is_active := true setget set_active`
- Determinism: use a local `RandomNumberGenerator` seeded from `seed`; never the global
  RNG. Advance a monotonic time accumulator; each half-cycle picks a direction from the
  seeded sequence (random unit vector in the horizontal plane + small vertical component),
  so the same seed + elapsed time reproduces the same impulse.
- `step(dt)` (called from `_physics_process`): if active and not expired, for each
  overlapping body:
  - `affect_player`: if body has `set_external_velocity`, add an oscillating offset
    `dir * impulse_strength` (use the existing `set_external_source_is_static(false)` if
    present, like `WindTunnelV2`). Do NOT overwrite a persistent wind vector — add to it.
  - `affect_rigid`: if body is `RigidBody` and mode != STATIC, `apply_central_impulse(dir *
    impulse_strength * dt * scale)`.
  - Camera feedback: once at trigger start, if `camera_amplitude > 0`, call
    `CinematicManager.trigger_camera_shake(duration, camera_amplitude, frequency)` (reuse —
    do not reimplement shake).
- Belongs to `replay_sync`; `get_snapshot()` / `restore_snapshot()` store/restore
  `is_active`, `seed`, and the time accumulator.

### B. Global ship-wide trigger (thin, no new autoload)

- Add OYS commands in `core_v2/systems/OYS_Interpreter.gd` (follow the existing
  `CAMERA_SHAKE` / `CAMERA_SHAKE_STOP` pattern):
  - `TREMOR duration amplitude frequency seed` — fans out to every node in group
    `tremor_zone` (call `set_active(true)` with the given params), then triggers the global
    camera shake via `CinematicManager`.
  - `TREMOR_STOP` — sets every `tremor_zone` node `set_active(false)`.
- `TremorZoneV2` adds itself to group `tremor_zone` in `_ready()`.

## Constraints

- Godot 3.x / GDScript 1.x: `yield` with strings, classic `connect()`, no `@onready`, no
  Godot 4 syntax.
- GLES2: physics impulses + emissive/energy only. No new transparency, no post-processing,
  no lightmap re-bake.
- Determinism: seeded local RNG, snapshot-able accumulator, `replay_sync` group.
- Reuse `WindTunnelV2`'s player/rigid contract (`set_external_velocity` /
  `apply_central_impulse`) and `CinematicManager.trigger_camera_shake` — do not duplicate.
- Composition over inheritance; signals, never `get_parent()` chains.
- Static typing in production code.
- Do not modify `WindTunnelV2`, `InteractableBaseV2`, or `CinematicManager` (only call it).

## Files to Modify

- `core_v2/components/TremorZoneV2.gd` (new)
- `core_v2/systems/OYS_Interpreter.gd` (add `TREMOR` / `TREMOR_STOP`)
- `core_v2/tests/test_tremor_zone.gd` (new)
- `docs/features/FD-288_tremor_zone.md` (this file)

## Verification

1. `./runtest.sh -a ./core_v2/tests/test_tremor_zone.gd` — same seed reproduces the same
   impulse sequence; player `external_velocity` oscillates; `PushableBoxV2` (RigidBody)
   receives impulse; snapshot/restore round-trips the accumulator; `is_active=false`
   culls processing.
2. `godot3 --headless --quit` in project root — no script errors on load.
3. `TREMOR` OYS command activates all `tremor_zone` nodes and triggers camera shake;
   `TREMOR_STOP` deactivates them.
