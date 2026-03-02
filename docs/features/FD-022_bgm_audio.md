# FD-022: BGM Audio Manager

**Status:** Planned
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-03-02

## Problem

Background music system needs reimplementation for Menu and Cryogenic chamber scenes.

## Solution

Reimplement `autoload/AudioManager.gd` with:
- Music track management
- Crossfade between tracks
- Zone-based music triggers

## Files to Modify

- `autoload/AudioManager.gd` (new/modify)
- Menu scene
- Cryo scene

## Verification

1. Music plays in menu
2. Music plays in cryo
3. Crossfade works between zones
