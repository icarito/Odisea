# FD-025: Tube / Airlock Connector Kit

**Status:** Planned
**Priority:** P0
**Effort:** Small
**Created:** 2026-03-02

## Problem

Need visual/physical connection between platform sections, interiors, airlocks
and centrifugal plates. For Acto I, the connector fantasy should bias toward
airlocks because that is the canonical Odisea transition language.

## Solution

Create a small connector kit rather than a single pipe:

- `TubeConnector.tscn`: simple traversable tube with deterministic static
  collision.
- `AirlockConnector.tscn`: short connector that can host
  `AirlockChamber.tscn` and a `TransitionPortal`.
- Shared visual/collision dimensions so level blocks can snap together.
- Optional camera helper anchors for close third-person interior framing.

Existing assets to reuse:

- `core_v2/props/AirlockChamber.tscn` 
- `core_v2/components/AirlockControllerV2.gd` - these two have no design value and were a weak attempt - don't reuse but discard.
- The IrisDoor on the other hand has nice looks and works well for an airlock.

- `core_v2/components/CameraZone.tscn` for constrained camera experiments

## Files to Modify

- `core_v2/components/TransitionPortal.gd` (dependency from FD-021)
- `scenes/common/TubeConnector.tscn` (new)
- `scenes/common/AirlockConnector.tscn` (new)

## Verification

1. Visual connection between sections
2. Player can traverse
3. Deterministic collision
4. Airlock connector can host a transition portal without clipping the player
5. Camera remains readable in constrained third-person framing
