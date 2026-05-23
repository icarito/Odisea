# Gravity and Physics Contracts

This document is the source of truth for agents working on gravity, terraces,
`WorldRotator`, `PlateContentStream`, zero-G, and scaffold systems.

Read this before changing:

- `core_v2/systems/GravityWorld.gd`
- `core_v2/systems/WorldRotator.gd`
- `core_v2/systems/PlateContentStream.gd`
- `core_v2/systems/DynamicGravityProxy.gd`
- `core_v2/player/ControllerManager.gd`
- `core_v2/player/ZeroGravityController.gd`
- `core_v2/levels/BaseTerrace.tscn`
- `core_v2/tests/TestWorldRotator.tscn`

Related feature docs:

- `docs/features/FD-036_gravity_manager.md`
- `docs/features/FD-037_infinite_scaffold_field.md`
- `docs/features/FD-038_zero_gravity_controller.md`
- `docs/features/FD-039_gravity_physics_strategy.md`
- `docs/features/FD-040_plate_content_stream_stability.md`

## Current State By FD

| FD | State | Notes |
|----|-------|-------|
| FD-036 | Implemented / continuing | `WorldRotator` and `GravityWorld` provide the walkable centrifugal frame. `BaseTerrace` is verified working in centrifugal mode. |
| FD-037 | Design / blocked by performance | Infinite scaffold must be canonical-space, mostly visual, and bounded. Current prototypes are too expensive for `BaseTerrace`. |
| FD-038 | Prototype / incomplete | Zero-G controller path exists, but angular control and near-axis zero/low-G integration remain unfinished. |
| FD-039 | Implemented strategy | Four stable gravity regimes are documented; `PlateContentStream` is the path for gameplay physics outside `WorldRotator`. |
| FD-040 | Verified / continuing | Sticky slot assignment, inspector `PlateSlotConfig`, and current-plate physics gating are active. `BaseTerrace` opts out of `WorldRotator` pool gating while legacy physics remains. |

## Coordinate System

Odisea uses an inverted forward axis:

- `+Z` is back / camera direction.
- `-Z` is forward.
- Do not assume standard Godot forward conventions when placing test objects,
  player starts, or camera-relative fixtures.

## Mental Model

There are two spaces:

- **Physical global space:** Godot physics space. `PlayerControllerV2` expects
  `Vector3.UP` and gravity toward global `Vector3.DOWN`.
- **Canonical ship space:** stable ship/terrace space before `WorldRotator`
  applies the current visual frame. Use `WorldRotator.to_canonical()` and
  `WorldRotator.from_canonical()` when a system must reason about the ship
  independent of the current visual rotation.

Walkable centrifugal gravity is a presentation and frame-management trick:

1. The player remains in standard Godot physics.
2. `WorldRotator` rotates the visible world so the selected terrace's walkable
   frame appears upright to the player.
3. `GravityWorld` computes canonical gravity vectors and blend state.
4. Camera/visual frame follows the player so switching plates feels like the
   world tilted rather than the player controller changing its up vector.

Do not add dynamic-up logic to `PlayerControllerV2`, `PlayerJumpV2`, or
`PlayerMovementV2` unless a future FD explicitly replaces this contract.

## Gravity Modes

Mode integer values are serialized. Keep `GravityModes.gd` values stable.

| Mode | Runtime owner | Gravity vector | Physics contract |
|------|---------------|----------------|------------------|
| `STANDARD_1G` | `PlayerControllerV2` | `Vector3.DOWN * one_g_strength` | Normal walkable Godot physics. |
| `SPIN_WALKABLE` | `PlayerControllerV2` + `WorldRotator` + optional `PlateContentStream` | Radial outward from the ship axis, blended with `Vector3.DOWN` by `gravity_blend` | Player still uses standard controller; world/camera frame changes. |
| `ZERO_G` | `ControllerManager` + `ZeroGravityController` | `Vector3.ZERO` | Separate inertial controller. No walking, snap, jump, or crouch semantics. |
| `SPIN_DYNAMIC` | `DynamicGravityProxy` opt-in | Radial outward from the ship axis | For selected dynamic props, not global static level geometry. |

### Blended Gravity

`GravityWorld.gravity_blend` blends standard down and centrifugal radial gravity:

- `0.0`: standard down.
- `1.0`: fully radial centrifugal.
- Between 0 and 1: diagonal gravity. Example: a 45 degree blend can simulate a
  damaged or partially spun terrace where gravity reads halfway between `-Y`
  and radial outward.

The terrace angle and gravity angle are related by default, but they are not the
same contract. Future narrative states may set gravity angle independently of
terrace angle.

### Centrifugal Strength

For radial modes, strength is radius-dependent:

- If `ship_angular_velocity_rad_s > 0`, strength is `omega^2 * radius`.
- Otherwise it scales against `centrifugal_reference_radius`.
- Near the ship axis, effective spin gravity can approach zero. Full integration
  of zero/near-zero bands is pending; do not fake it by changing the walking
  controller's up vector.

## WorldRotator Contract

`WorldRotator` is a `tool` script, so editor safety is critical.

Editor mode:

- Must not rotate, re-anchor, select plates, or reset transforms in
  `Engine.editor_hint`.
- Must not mutate `BaseTerrace.tscn` authoring transforms when the scene is
  opened or saved.
- Any runtime reset, scene-anchor application, or plate selection must happen
  after returning from the editor-hint guard.

Runtime mode:

- May reset its global transform before canonical calculations.
- Selects the active terrace plate and rotates toward that plate's frame.
- Provides `to_canonical()` and `from_canonical()` for systems that stream,
  spawn, or query by stable ship coordinates.
- Emits `platform_changed` for non-physics side effects and manager state.

Signals must not drive deterministic physics state. Physics state changes belong
in `_physics_process()` or explicit deterministic calls.

## Physics Under WorldRotator

Godot 3 physics does not make arbitrary `StaticBody`/`RigidBody` children safe
under a rotating parent. Rotating `WorldRotator` can effectively move physics
bodies in global physics space.

Default rule:

- Gameplay physics should live outside `WorldRotator`.
- Visual-only nodes may live inside `WorldRotator`.
- If physics remains under `WorldRotator`, document it as legacy and keep the
  scene opt-out from aggressive current-plate-only physics.

`BaseTerrace` is currently legacy/hybrid:

- It works in centrifugal mode.
- It still has gameplay physics under `WorldRotator`.
- Therefore `BaseTerrace.tscn` explicitly sets
  `WorldRotator.centrifugal_current_plate_only_physics = false`.
- Do not remove that override until its gameplay physics has moved to
  `PlateContentStream` or another stable global-space owner.

## PlateContentStream Contract

`PlateContentStream` owns streamed gameplay content for plates.

Required layout:

```text
LevelRoot
+-- Player/Pilot
+-- WorldRotator
|   +-- visual terrace/spiral/hull/scaffold content
+-- PlateContentRoot
    +-- PlateContentSlot_*
        +-- streamed gameplay subscene
```

Rules:

- `PlateContentRoot` must be outside `WorldRotator`.
- Slots are in physical global space.
- Slot transforms are recomputed from
  `WorldRotator.global_transform * plate_canonical_transform`.
- Slot assignment is sticky while a plate remains in the active window.
- Inspector authoring uses `PlateSlotConfig` children under `PlateContentRoot`.

Physics gating:

- `PlateContentStream.centrifugal_current_plate_only_physics = true` keeps
  streamed content visible but disables collision/physics outside the selected
  plate in centrifugal mode.
- This is safe for streamed content whose active physics should be limited to
  the current walkable frame.
- Do not apply this assumption to legacy content inside `WorldRotator`.

## DynamicGravityProxy Contract

`DynamicGravityProxy` is opt-in per prop or zone.

Use it for:

- Selected `RigidBody` props that should visibly fall radially.
- Prototype or localized SPIN_DYNAMIC experiments.

Do not use it for:

- Static floors/walls.
- Global player gravity.
- Large sets of distant decorative objects.

Coriolis and radial forces must remain bounded and deterministic.

## Zero-G Contract

Zero-G is a separate controller path, not a flag inside `PlayerControllerV2`.

Rules:

- `ControllerManager` switches `ZERO_G` to `ZeroGravityController`.
- 1G walking behavior, jump, snap, and crouch do not apply in zero-G.
- Rotation/angle control for zero-G remains incomplete; future work must define
  angular authority explicitly.
- Near-axis spin regions may become zero/near-zero zones later, but should route
  through gravity zones/controller switching, not through dynamic-up hacks.

## Infinite Scaffold Contract

The infinite scaffold field is not production-ready.

Current guidance:

- Treat it as visual infrastructure, not gameplay collision.
- Keep generation decisions in canonical ship space.
- Visual nodes may live under `WorldRotator` so they share the current frame.
- Streaming/recycling must use `WorldRotator.to_canonical()` or equivalent
  stable coordinates to avoid popping.
- The current prototype has performance risk. Do not add thousands of nodes or
  unbounded chunk rebuilds to `BaseTerrace`.

Open work:

- Integrate scaffold streaming with `WorldRotator` without increasing the
  already tight performance budget.
- Reintroduce the lost fan/ventilator-style visual beat, ideally as cheap visual
  dressing or localized wind gameplay, not as global physics.

## Verification

Focused checks before touching this area:

```bash
python3 scripts/check_tracked_imports.py
python3 scripts/check_critical_import_artifacts.py
./runtest.sh -a ./core_v2/tests/test_gravity_modes.gd
./runtest.sh -a ./core_v2/tests/test_dynamic_gravity_proxy.gd
./runtest.sh -a ./core_v2/tests/test_plate_content_stream.gd
./runtest.sh -a ./core_v2/tests/test_world_rotator.gd
./runtest.sh -a ./core_v2/tests/test_trenchbroom_common_prop_controls.gd
```

`test_trenchbroom_common_prop_controls.gd` may return exit code 101 for known
orphan/leak warnings while still reporting no failed tests. Treat real failed
assertions separately.

For `BaseTerrace` gameplay smoke:

```bash
./runtest.sh --nodet --oys test_baseterrace_killzone
```

The deterministic replay version of that OYS can be sensitive to snapshot drift;
use the focused GdUnit tests above to validate current contracts before changing
snapshots.
