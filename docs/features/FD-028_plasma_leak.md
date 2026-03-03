# FD-028: Plasma Leak Obstacle

**Status:** Planned
**Priority:** Low
**Effort:** Small
**Created:** 2026-03-02

## Problem

Environmental hazard: plasma leaks that damage/push player.

## Solution

Create `scenes/common/PlasmaLeak.tscn`

- Area-based damage zone
- Visual particle effects
- Push force applied to bodies

## Files to Modify

- `scenes/common/PlasmaLeak.tscn` (new)

## Verification

1. Particles render correctly
2. Player pushed/damaged in zone
3. Deterministic behavior in replay
