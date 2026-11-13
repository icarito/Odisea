# FD-025: Tube / Airlock Connector Kit

**Status:** Design
**Priority:** P0
**Effort:** Small
**Created:** 2026-03-02
**Depends on:** FD-021 (Scene Transition / TransitionPortal) — Implemented

## Problem

Need visual/physical connection between platform sections, interiors, airlocks
and centrifugal plates. For Acto I, the connector fantasy should bias toward
airlocks because that is the canonical Odisea transition language.

There is already a partial tube vocabulary in `core_v2/props/tube/`
(`TubeSection`, `TubeRing`, `TubeAirlock`) plus `IrisDoorV2` and
`TransitionPortal`. What is missing is a **coherent kit with shared snap
dimensions**: pieces today are standalone scenes with ad-hoc sizes, so level
blocks cannot reliably align or be traversed deterministically.

## Design decisions

### Shared snap dimensions (single source of truth)

Define constants in a new `core_v2/components/ConnectorKit.gd` (autoload-free,
just a `class_name` with constants) so every kit scene and the authoring
workflow reads the same numbers:

| Constant | Value | Origin |
|---|---|---|
| `TUBE_RADIUS_OUTER` | 4.0 m | `TubeSection` cylinder radius |
| `TUBE_RADIUS_BORE` | 2.7 m | `TubeRing` radius / `TubeAirlock` inner frame |
| `TUBE_LENGTH` | 9.0 m | `TubeSection` cylinder height |
| `AIRLOCK_LENGTH` | 6.0 m | `TubeAirlock` frame depth + door canopy |
| `DOOR_RADIUS` | 1.7 m | `IrisDoorV2.iris_radius` |
| `PORTAL_HALF_EXTENTS` | (1.2, 1.4, 0.35) | `TransitionPortal.tscn` BoxShape |

**Snap rule:** every connector is authored with its long axis along **Z**,
origin at center, and its two connection faces at `z = ±L/2`. The player
traverses a connector aligned to +Z (forward), consistent with the project's
`-Z = forward` convention only for *movement*; the kit itself uses +Z as the
layout axis so connectors read left-to-right in the editor.

### 1. `TubeConnector.tscn` (new, `core_v2/props/tube/TubeConnector.tscn`)

Simple traversable tube segment with deterministic static collision:

- Root `Spatial` named `TubeConnector`.
- `MeshInstance` reusing a `TubeSection`-derived mesh (solid interior material,
  not the current transparent one) with `TUBE_RADIUS_OUTER`.
- `StaticBody` `Collision` — **StaticBody, not Area**: deterministic, cheap,
  no body_entered signals. Capsule or cylinder shape with radius
  `TUBE_RADIUS_BORE`, half-length `TUBE_LENGTH/2`.
- `Snap_A` / `Snap_B` marker nodes at `z = ±TUBE_LENGTH/2` (for editor
  snapping and for level-block placement helpers).
- Optional `CameraZone` child (reusing `core_v2/components/CameraZone.tscn`)
  with a `CinematicRigV2` anchor at the tube center for close third-person
  framing in constrained interiors.

### 2. `AirlockConnector.tscn` (new, `core_v2/props/tube/AirlockConnector.tscn`)

Short connector that can host an airlock chamber and a transition portal:

- Root `Spatial` named `AirlockConnector`, length `AIRLOCK_LENGTH`.
- Reuses `IrisDoorV2.tscn` at one end (canonical Odisea airlock language) and
  a `TransitionPortal` (from FD-021) at the other, wired to the same scene
  spawn flow `TubeAirlock` already uses.
- `StaticBody` collision matching `TUBE_RADIUS_BORE` so the player traverses
  without clipping; the Iris door keeps its own opening logic.
- `TransitionPortal` configured with `transition_style = "airlock"` and a
  `target_airlock_path` so the airlock cycle plays before the scene change
  (same path as `AirlockZoneV2`).
- Optionally hosts `AirlockChamber.tscn` (`core_v2/props/doors/`) inside when
  a pressurized chamber is desired for the section.

### 3. Authoring workflow helper

- `core_v2/components/ConnectorKit.gd` exposes:
  - `snap_position(connector: Spatial, face: String) -> Vector3` — returns the
    world position of `Snap_A`/`Snap_B`.
  - `connect_a_to_b(a: Spatial, b: Spatial)` — aligns `B`'s `Snap_A` to `A`'s
    `Snap_B` (position + rotation), used by future level-block tooling.
- Existing assets renamed/kept as-is: `TubeAirlock` stays as the legacy
  auto-transition piece; `TubeSection`/`TubeRing` become the visual vocabulary
  referenced by the kit (no delete, no rework of legacy levels).

### Explicitly discarded

Per the original FD: `AirlockChamber.tscn` (at `core_v2/props/`) and
`AirlockControllerV2.gd` (at `core_v2/components/`) are **not** reusable for
this kit — they were weak attempts and are superseded by `AirlockZoneV2` +
`TransitionPortal`. The current `AirlockChamber.tscn` lives at
`core_v2/props/doors/AirlockChamber.tscn` and is fine to host inside the
connector, but the old `components/AirlockControllerV2.gd` path is not part of
the kit.

## Files to modify/create

- `core_v2/components/ConnectorKit.gd` (new — shared constants + snap helpers)
- `core_v2/props/tube/TubeConnector.tscn` (new)
- `core_v2/props/tube/AirlockConnector.tscn` (new)
- `core_v2/components/CameraZone.tscn` (reused, no change)
- `core_v2/components/TransitionPortal.gd` (reused; no change required)

## Verification

1. Load both connectors in `TestScene_v2.tscn`; snap `TubeConnector` face-to-
   face with `AirlockConnector`; assert faces align (unit test via
   `ConnectorKit.snap_position`).
2. Player (Pilot_v2) can traverse `TubeConnector` end-to-end; no jitter and no
   collision gaps in the bore.
3. `AirlockConnector` host a `TransitionPortal`; entering triggers the airlock
   cycle (Iris door) then the scene transition — no player clipping during the
   cycle.
4. Camera remains readable in constrained third-person framing (CameraZone
   helper anchor works).
5. Determinism: `runtest.sh -a core_v2/tests/test_determinism_v2.gd` passes
   with a level containing both connectors; no `_process`-only logic in the
   collision path.
