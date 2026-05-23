# FD-024: Guardrail Platform

**Status:** Planned
**Priority:** Medium
**Effort:** Small
**Created:** 2026-03-02

## Problem

Platform variant with safety railings for player safety on edges.

## Solution

Create `scenes/common/GuardrailSegment.tscn`

- Based on MovingPlatformV2 pattern
- Static platform with rail meshes
- Collision shapes for player detection

## Files to Modify

- `scenes/common/GuardrailSegment.tscn` (new)
- Test scene

## Verification

1. Player can walk on platform
2. Railings prevent falling
3. Works with deterministic replay
