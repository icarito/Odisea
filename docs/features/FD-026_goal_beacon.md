# FD-026: Goal Beacon

**Status:** Planned
**Priority:** Medium
**Effort:** Small
**Created:** 2026-03-02

## Problem

High-contrast objective marker for level completion.

## Solution

Create `scenes/common/GoalBeacon.tscn`

- Visual beacon (light/particle)
- Trigger zone for level completion
- High contrast for visibility

## Files to Modify

- `scenes/common/GoalBeacon.tscn` (new)

## Verification

1. Beacon visible from distance
2. Trigger activates on player contact
3. Level completion event fires
