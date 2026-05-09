# FD-034: Player Interaction Hints

**Status:** Planned
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-05-08
**Completed:** -

## Problem

Interaction hints were routed through the subtitle overlay, so player prompts behaved like transient subtitle lines: styled panels, stacking/fade behavior, and stream-like timing. Interaction guidance needs to be a quiet HUD status label that only appears while relevant.

## Solution

Implement a dedicated player hint overlay:

- one fixed top-left label
- no background, border, panel, stacking, or animation
- hidden unless an interactable prompt or script hint is active
- safe-margin aware through `OverlayUIManager`
- never displays any single hint for more than 30 seconds

Automatic hints show only the current best interactable selected by `PlayerControllerV2`. Manual script hints are available through OYS and temporarily override automatic hints while interactive gameplay is active.

### Considered Options

- **Use SubtitlesOverlay `show_hint()`**: Minimal code, but preserves the intrusive subtitle styling and stream behavior.
- **Dedicated HUD label**: Keeps interaction guidance separate from subtitles and matches the fixed status requirement.
- **Selected**: Dedicated HUD label managed by `PlayerHintManager`.

## Files to Modify

- `core_v2/autoloads/PlayerHintManager.gd` (new)
- `core_v2/ui/overlay/PlayerHintOverlay.tscn` (new)
- `core_v2/ui/overlay/PlayerHintOverlay.gd` (new)
- `core_v2/player/PlayerControllerV2.gd` (modify)
- `core_v2/systems/OYS_Parser.gd` (modify)
- `core_v2/systems/OYS_Interpreter.gd` (modify)
- `core_v2/systems/OYS_Resolver.gd` (modify)
- `project.godot` (modify autoloads)

## Verification

1. Enter range of an interactable and confirm one top-left text hint appears.
2. Leave range and confirm the hint clears.
3. Run `HINT "message" 30` in an interactive OYS script and confirm it appears as the same top-left label.
4. Run `CINEMATIC` or `CINEMATIC_START` and confirm hints are hidden/suppressed until `INTERACTIVE` or `CINEMATIC_STOP`.
5. Run targeted tests:
   ```shell
   ./runtest.sh -a ./core_v2/tests/test_player_hint_manager.gd
   ./runtest.sh -a ./core_v2/tests/test_oys_logic.gd
   ```
6. Run the full suite before merge:
   ```shell
   ./runtest.sh
   ```
