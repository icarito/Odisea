# FD-041: PlateContentStream Stability and Inspector Authoring

**Status:** Pending Verification
**Priority:** High
**Effort:** Small
**Created:** 2026-05-21
**Depends on:** FD-040

## Problem

`PlateContentStream` originally reassigned active slots by sorted candidate index every refresh. When two nearby plates swapped distance order, the stream treated the same content as a different slot assignment, cleared the old slot children, and instantiated the scene again. For interactive content this looked like disappearing props; for `RigidBody` content it also caused visible jitter because bodies restarted from their initial scene state.

Push animation had a related visual issue: `visual_push_correction` jumped directly to the current raycast distance every physics frame, so small rigid-body jitter could move the pilot hands abruptly.

## Implementation

### Sticky slot assignment

`core_v2/systems/PlateContentStream.gd` now keeps a key-to-slot binding while the key remains in the active candidate set:

1. Collect and sort candidate plates by distance.
2. Limit candidates to the active window (`slot_pool_size`).
3. Preserve any existing slot whose key is still active.
4. Fill only free slots with newly active keys.
5. Deactivate slots whose key left the active window.

This keeps child scenes alive across distance-order changes and only destroys content when the plate leaves the streamed range or the assigned scene changes.

### Pushable content settling

`core_v2/tests/PlateContentPushBoxes.gd` settles pushable rigid bodies recursively on ready. Streamed test content starts stable in kinematic mode and can still wake through the normal `PushableBoxV2.wake_up()` path.

### Smoothed visual push correction

`core_v2/player/PlayerControllerV2.gd` now smooths `visual_push_correction` with a 15 Hz lerp. The logical push state is unchanged; only the visual anchor consumed by `PilotAnimatorV2` is filtered.

### Inspector authoring

`core_v2/systems/PlateSlotConfig.gd` is a lightweight `Node` for authoring plate assignments in the Inspector:

```gdscript
export(int) var spiral_idx := 0
export(int) var plate_idx := 0
export(PackedScene) var content_scene
```

On `_ready()`, `PlateContentStream` scans direct children that are `PlateSlotConfig` and calls `assign_scene()` for each one. `BaseTerrace.tscn` now includes an example `PlateSlotConfig_0_12` under `PlateContentRoot`.

## Verification

Focused automated tests:

```bash
./runtest.sh -a ./core_v2/tests/test_plate_content_stream.gd
./runtest.sh -a ./core_v2/tests/test_world_rotator.gd
```

Manual pass for the gameplay feel:

```bash
./runtest.sh --show --oys test_push_integration
```

Open `core_v2/tests/TestWorldRotator.tscn`, move between nearby terraces, and confirm streamed boxes keep their state instead of disappearing or jittering on slot refresh.
