# Features Stashed & Pending Integration

This document tracks features and fixes currently in the **Git Stash** and identified in recent **Conversation History**.

## 🟢 Odyssey Script (OYS) Improvements
- [ ] **OYS Subtitles Integration**: Display `PRINT` and `ASSERT` strings as on-screen subtitles.
- [ ] **OYS `CLS` Command**: Add support for clearing subtitles via script.
- [ ] **Subtitles UI Refinement**:
    - [ ] Migrate `SubtitlesOverlay` from `Spatial` to `CanvasLayer` (Layer 120).
    - [ ] Implement automatic width/height calculation based on text content and font.
- [ ] **Assert Color Highlighting**: Route OYS assertions through `OYS_Console` using `green` for success and `red` for failure.

## 🟡 Audiovisual integration
- [ ] **Jump Sound**: Trigger the `jump.wav` sound effect when the player executes a jump. Integration point: `PlayerAnimatorV2.gd`.

## 🔴 Replay & Stability
- [ ] **GDUnit Replay Timeouts**: Fix the timeout issues occurring in `test_locomocion_adela` and `test_cargol_basic.oys`.
- [ ] **SessionManager Determinism**: Review recent logs for positional drift or frame mismatches during high-stress replays.

---
*Note: This list is derived from `git stash@{0}` and the conversations starting from 2026-02-14.*
