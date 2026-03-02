# FD-027: Spawn Cinematic / ScreenBorders

**Status:** Planned
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-03-02

## Problem

Player spawn needs cinematic camera and screen effects.

## Solution

From TODO.md:

- `scenes/common/ScreenBorders.tscn` - Cinematic frame effects
- `scripts/SceneSpawn.gd` - Spawn animation

## Files to Modify

- `scenes/common/ScreenBorders.tscn` (new)
- `scripts/SceneSpawn.gd` (new/modify)

## Verification

1. Cinematic plays on spawn
2. Borders visible during intro
3. Transitions to gameplay smoothly
