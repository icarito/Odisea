# FD-021: Scene Transition System

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-03-02

## Problem

Need seamless transitions between level sections/rooms in the colony ship.

## Solution

See existing spec: `docs/scene_transition_system.md`

## Files to Modify

- `core_v2/sim/SceneTransition.gd` (new)
- Level scenes

## Verification

1. Player walks through transition
2. New area loads
3. Player position preserved correctly
