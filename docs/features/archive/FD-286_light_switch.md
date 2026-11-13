# FD-286: Light switch + light group (interruptor de luz conmutable)

**Status:** Completed
**Priority:** High
**Effort:** Small
**Created:** 2026-09-01
**Completed:** 2026-09-01

## Problem

The dome lighting props already know how to turn on/off: `SciFiStaticLightV2`,
`SciFiHangingLightV2`, `FluorescentLight`, etc. inherit `PropBaseV2` → `InteractableBaseV2`,
so `set_active(bool)` animates `anim_progress` and `_update_visuals()` drives
`light_energy` / `emission_energy` down to zero (off) or up to full (on).

What is missing is the **authoring side**: there is no dedicated wall light-switch prop, and
no declarative way to bind one switch to a set of lights without wiring the generic
`LogicCircuitManager` (which FD-283 restricts to the sealed AuxPower door only).

Goal: a player flips a wall switch → a defined group of lights turns on/off together, using
only the existing interactable contract. No new lighting model, no re-bake.

## Solution

### A. `LightSwitchV2` — wall switch prop

- New prop `core_v2/props/controls/LightSwitchV2.gd` + `.tscn`, extends `InteractableBaseV2`.
  Verbo de interacción: "accionar" (Spanish, no anglicisms).
- Binary state only: `interact()` already toggles `is_active` (inherited). No custom logic.
- Visual: a wall-mount sci-fi switch plate (simple low-poly mesh, generated or built from
  primitives — no external asset). Style must match the existing fixture language
  (matte body + small emissive status strip/lens that reads ON when `is_active` and OFF
  otherwise). Use `anim_progress` for the visual, exactly like the other props.
- Emits the inherited `activated` / `deactivated` signals on animation completion (already
  emitted by `InteractableBaseV2._on_animation_completed()`).
- Determinism: belongs to `replay_sync` group, overrides `get_snapshot()` /
  `restore_snapshot()` (call `super` and include `is_active` — already covered by the base,
  so only add if the switch has extra local state).
- **No dependency on `DomeLightState` (FD-284).** The switch is free-standing; any dome-state
  gating is a later concern and must NOT be wired here.

### B. `LightGroup` — declarative switch→lights binding

- New component `core_v2/components/LightGroup.gd` (Node, not a prop).
- Exports:
  - `export(NodePath) var switch_path` — the `LightSwitchV2` (or any node with
    `activated`/`deactivated` signals) that drives the group.
  - `export(Array, NodePath) var light_paths = []` — explicit list of light props.
  - `export(String) var scene_group := ""` — optional: also apply to all nodes in a scene
    group (e.g. `"dome_wall_lights"`), so a switch can drive a set without editing each prop.
- At `_ready`: resolve `switch_path`, connect its `activated` → `_set_all(true)` and
  `deactivated` → `_set_all(false)`. Resolve `light_paths` + `scene_group` into a cached
  list of target nodes (deduplicated).
- `_set_all(value: bool)`: for each cached target, if it has `set_active` call
  `set_active(value)`; if it has `is_active` only, set it; otherwise ignore. This keeps the
  binding tolerant to both `PropBaseV2` lights and plain `Light` nodes (for a plain
  `Light`, set `visible` and/or `light_energy` — lights should read off via `set_active`
  where available).
- `_apply_initial()`: on ready (deferred one frame), push the switch's current `is_active`
  to the group so scene-authored state stays consistent on load.
- Determinism: `LightGroup` itself is read-only pass-through; add it to `replay_sync` and
  implement `get_snapshot()` / `restore_snapshot()` that store/restore the resolved
  `switch_path` state (delegate to the switch). It must not mutate gameplay signals — only
  propagate.

## Constraints

- Godot 3.x / GDScript 1.x: `yield` with strings, classic `connect()`, no `@onready`, no
  Godot 4 syntax.
- GLES2: no new transparency, no new post-processing. Toggling lights is
  `light_energy`/`emission_energy` via existing `anim_progress`; never a lightmap re-bake.
- Composition over inheritance; signals, never `get_parent()` chains.
- Static typing in production code.
- Do not modify `LogicCircuitManager` or `InteractableBaseV2`.

## Files to Modify

- `core_v2/props/controls/LightSwitchV2.gd` (new)
- `core_v2/props/controls/LightSwitchV2.tscn` (new)
- `core_v2/components/LightGroup.gd` (new)
- `core_v2/tests/test_light_switch.gd` (new)
- `docs/features/FD-286_light_switch.md` (this file)

## Verification

1. `./runtest.sh -a ./core_v2/tests/test_light_switch.gd` — switch toggles `is_active`;
   `LightGroup` propagates to all `light_paths` + `scene_group` targets; snapshot/restore
   round-trips the switch state.
2. `./test_prop.sh LightSwitchV2 --editor-path=$(which godot3)` — switch renders and the
   emissive strip differs between idle/active (screenshot delta check passes).
3. `godot3 --headless --quit` in project root — no script errors on load.
4. Screenshot of the switch (off and on) attached to the PR.
