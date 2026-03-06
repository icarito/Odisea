# FD-027: Screen Effects Overlay (Death Blink / Script Cinematic Bars)

**Status:** In Progress
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-03-02

## Problem

`core_v2` still relies on legacy ideas for death/cinematic screen coverage:

- KillZone respawn has no polished mask, so the player swap is visible.
- OYS cinematics (`CINEMATIC_START` / `CINEMATIC_STOP`) have no panoramic frame effect.
- Overlay logic was fragmented across unrelated UI singletons.

## Solution

Implement a unified screen effects path on top of `OverlayUIManager`:

- `ScreenEffectsManager` autoload for orchestration.
- `ScreenEffectsOverlay.tscn` hosted in the passive overlay slot.
- One shader-driven full-screen mask with two modes:
  - Curved eyelid blink for death/respawn.
  - Straight panoramic bars for OYS script cinematics only.

### Death / Respawn

- Trigger from `TeleportSystem._on_player_killed()`.
- Close eyelids, respawn while covered, reopen.
- No wait-for-key death screen in v1; keep the loop fast and deterministic.
- Optional centered `ODISEA` label while fully covered.

### Script Cinematics

- Trigger only from OYS `CINEMATIC_START` / `CINEMATIC_STOP`.
- Camera zones do not automatically enable bars.
- Bars animate in/out independently from subtitles and touch UI.

### Technical Goals

- No per-frame polling for the effect lifecycle.
- No input capture.
- Respect mobile safe areas via `OverlayUIManager`.
- All implementation lives under `core_v2/`.

## Files to Modify

- `core_v2/autoloads/ScreenEffectsManager.gd`
- `core_v2/ui/overlay/ScreenEffectsOverlay.tscn`
- `core_v2/ui/overlay/ScreenEffectsOverlay.gd`
- `core_v2/ui/overlay/ScreenEffectsOverlay.shader`
- `core_v2/systems/TeleportSystem.gd`
- `core_v2/systems/OYS_Interpreter.gd`

## Verification

1. Falling into `KillZoneV2` covers the respawn with a blink.
2. `CINEMATIC_START` shows straight cinematic bars.
3. `CINEMATIC_STOP` removes the bars cleanly.
4. Overlay coexists with subtitles/mobile HUD without blocking input.
