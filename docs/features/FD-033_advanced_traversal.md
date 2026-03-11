# FD-033: Advanced Traversal Systems

**Status:** In Progress
**Priority:** High
**Effort:** Large
**Created:** 2026-03-11
**Completed:** -

## Problem

Odisea needs a deterministic traversal layer for vertical navigation and hand-authored movement affordances inside `core_v2`. The current branch proves the need for:

- ladder climbing that snaps cleanly to authored anchors and exits reliably at the top
- ledge hanging and mantle flow with readable interaction rules
- a reusable scene and prop workflow for manual validation before broad test automation

The feature must preserve replay determinism. Traversal cannot depend on variable-rate tweening, hidden visual offsets, or direct input polling inside state logic.

## Solution

Implement traversal as a deterministic simulation subsystem owned by `PlayerControllerV2` and executed from `_physics_process(delta)` through `TraversalLogicV2.step(dt, ...)`.

The feature is split into phases so the current PR can land a coherent vertical slice without overcommitting unfinished systems.

### Phase 1: Ladder and Ledge Core

Deliver a first deterministic traversal slice with:

- `LadderV2` interactables for vertical 1D climbing
- `LedgeV2` interactables for hanging and mantle
- explicit anchor-based state entry (`enter_climbing`, `enter_hanging`)
- deterministic position stepping inside `TraversalLogicV2`
- a manual sandbox scene for runtime tuning: `core_v2/levels/TestScene_Traversal.tscn`

Current interaction contract:

- ladder entry is automatic when the player pushes toward a valid ladder target
- ledge entry requires an explicit hold gesture (`crouch`) to avoid accidental grabs
- ladder top exit is automatic when the player reaches the climb boundary while continuing upward
- mantle starts from `HANGING` when the player pushes upward/forward without the hang-hold gesture

### Phase 2: Surface Climbing

Extend the traversal model to support climbable wall surfaces:

- 2D motion on authored climbable planes
- deterministic surface-local movement axes
- binary state transitions based on authored detection volumes, not freeform physics
- explicit exit conditions at edges, drops, or jump cancel

This phase must reuse the same state-machine rules as ladders and ledges rather than introducing a second traversal controller.

### Phase 3: Rope and Swing Traversal

Add deterministic traversal for ropes, pendulums, and vertical traversal props:

- rope slide with constant-step progression along an authored vector
- swinging based on deterministic trigonometric stepping or lookup-table math
- no reliance on Godot rigid body simulation for player state progression

### Phase 4: Visual Alignment and IK

Add a visual-only animation alignment layer once core traversal logic is stable:

- update end-effector targets from logical anchor data
- keep IK and mesh presentation strictly out of authoritative movement logic
- drive visual interpolation via `anim_progress` and authored target nodes

## Deterministic Rules

The traversal system follows these non-negotiable rules:

1. Input isolation: traversal logic consumes buffered input passed by `PlayerControllerV2`; it never polls `Input.*` directly.
2. Fixed logical stepping: traversal state uses constant-step movement and explicit clamps instead of tweens or freeform interpolation on authoritative position.
3. State and visuals are decoupled: logic owns state, anchors, normals, and progress; visual nodes only mirror that state.
4. Physics-frame authority: traversal simulation runs from `_physics_process(delta)` and is snapshot-friendly for replay.
5. Authored anchors over broad collision guesses: ladders and ledges expose anchor/normal data to avoid clipping and ambiguous entry.

## Considered Options

- **Option A**: Tween-driven traversal attached to scene props - faster to prototype, but nondeterministic and difficult to replay exactly.
- **Option B**: Full rigid-body traversal using Godot physics constraints - high implementation cost and poor control over replay drift.
- **Selected**: Authoritative traversal state machine in `core_v2` with prop-provided anchors and deterministic step logic.

## Files to Modify

- `core_v2/player/PlayerControllerV2.gd` (modify)
- `core_v2/player/traversal/TraversalLogicV2.gd` (modify)
- `core_v2/components/LadderV2.gd` (modify)
- `core_v2/components/LadderV2.tscn` (modify)
- `core_v2/components/LedgeV2.gd` (modify)
- `core_v2/components/LedgeV2.tscn` (modify)
- `core_v2/levels/TestScene_Traversal.tscn` (new)
- `core_v2/tests/climbing_validation.oys` (modify)

Potential future files for later phases:

- climbable surface component(s) under `core_v2/components/`
- rope or pendulum traversal component(s) under `core_v2/components/`
- visual target and IK support under `core_v2/actors/` or animation helpers

## Runtime Contracts

### Ladder

- exposes climb anchor and surface normal
- constrains movement to a 1D local vertical band
- provides authored climb limits for reliable auto-exit
- never requires `interact` once the player is aligned and pushing into the traversal target

### Ledge

- exposes a hang anchor point and facing normal
- allows explicit hanging entry, not accidental auto-grab during normal locomotion
- supports hanging hold, shimmy extension in future phases, and mantle
- keeps camera free while hanging

### Player Controller

- remains the owner of input buffering, camera update order, and traversal dispatch
- may suppress gravity or locomotion only through traversal state, not ad hoc flags spread through props
- must continue to support deterministic replay and snapshot restore flows

## Verification

1. Open `core_v2/levels/TestScene_Traversal.tscn` and verify ladder entry, top auto-exit, ledge hang, and mantle manually.
2. Confirm traversal state transitions in runtime inspection:
   - `current_state`
   - `is_active`
   - `is_climbing`
   - `is_hanging`
   - `_current_interactable`
3. Run `OYS_AUTO_RUN=res://core_v2/tests/climbing_validation.oys godot3-bin --path .` and verify traversal assertions after the manual scene is stable.
4. Run targeted deterministic checks:
   - `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd`
5. Once the feature slice is stable, run the broader suite:
   - `./runtest.sh`

## Open Questions

- Should ledge hanging remain gated by `crouch`, or become a configurable traversal gesture?
- Do ladder and ledge anchors need editor gizmos or dedicated preview meshes beyond the current `tool` previews?
- Should wall climbing ship in the same FD as ladders and ledges, or split into a follow-up FD once the core contracts are proven?
- For rope swinging, do we standardize on lookup-table trig immediately, or wait until the feature is closer to implementation?
