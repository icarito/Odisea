# FEATURE_INDEX.md — Odisea Acto I

## Active Features

| FD | Title | Status | Effort | Priority |
|----|-------|--------|--------|----------|
| FD-019 | Multiplayer Split-screen | In Progress | Large | High |
| FD-020 | WallManager Area | In Progress | Medium | Medium |
| FD-021 | Scene Transition System | Design | Medium | High |
| FD-022 | BGM Audio Manager | Planned | Medium | Medium |
| FD-025 | Tube Connector | Planned | Small | Medium |
| FD-026 | Goal Beacon | Planned | Small | High |
| FD-027 | Spawn Cinematic / ScreenBorders | Planned | Medium | Medium |
| FD-028 | Plasma Leak Obstacle | Planned | Small | Low |
| FD-029 | DDC Drone | Planned | Medium | Low |
| FD-030 | Cargol NPC | Planned | Medium | Medium |
| FD-031 | Narrative Dialogs (IA) | Planned | Large | Low |
| FD-032 | Seamless Startup Streaming | In Progress | Large | High |

## Completed

| FD | Title | Completed | Notes |
|----|-------|-----------|-------|
| FD-001 | OdysseyScript DSL | 2026-01-07 | Core testing framework |
| FD-002 | OdysseyScript Replay | 2026-01-07 | Deterministic replay |
| FD-003 | Test Runner (GDUnit3) | 2026-01-07 | Automated regression |
| FD-004 | PushableBoxV2 | 2026-01-10 | Hybrid rigid/cinematic |
| FD-005 | Movement Gamefeel | 2026-01-12 | Refined player feel |
| FD-006 | Sidescroller Zone | 2026-01-12 | |
| FD-007 | Test Battery | 2026-01-13 | |
| FD-008 | ANNA Agent (ML/CV) | 2026-02-15 | TCP bridge, sensors |
| FD-009 | Interaction System | 2026-02-17 | InteractableBaseV2 |
| FD-010 | OLCS (Logic Circuit) | 2026-02-17 | |
| FD-011 | Props Pipeline | 2026-02-17 | Validation system |
| FD-012 | Elevator | 2026-02-17 | |
| FD-013 | HoloTerminal Cinematic | 2026-02-20 | `core_v2/props/HoloTerminalV2.tscn` + CameraZone |
| FD-014 | VCamera Integration | 2026-02-21 | `core_v2/camera/VCameraSystemRig.gd`, OYS VCAMERA_* commands |
| FD-015 | Subtitles PRINT/ASSERT | 2026-02-19 | `core_v2/ui/retro/SubtitlesOverlay.tscn` |
| FD-016 | Retro UI Workbench | 2026-02-18 | `core_v2/ui/retro/DebugOverlay.tscn` |
| FD-017 | Emitter/Destroyer Areas | 2026-02-17 | `core_v2/components/PropEmitterArea.gd`, `PropDestroyerArea.gd` |
| FD-018 | Automatic Prop Zoo | 2026-02-16 | `core_v2/tests/TestScenePropZoo.gd` |
| FD-024 | Guardrail Platform | 2026-03-02 | `scenes/common/GuardrailSegment.tscn` |

---

## Status Legend

- **Planned**: Identified, not yet designed
- **Design**: Actively designing the solution
- **Open**: Designed, ready for implementation
- **In Progress**: Currently being implemented
- **Pending Verification**: Code complete, awaiting runtime verification
- **Complete**: Verified working, ready to archive
- **Deferred**: Postponed indefinitely
- **Closed**: Won't do

## First Level Focus (MVP Acto I)

**What's done:**
- ✓ FD-013 HoloTerminal Cinematic
- ✓ FD-014 VCamera Integration  
- ✓ FD-023 WindZone (`IndustrialFan.gd`, `WindTunnelV2.gd`)
- ✓ FD-024 Guardrail Platform

**Still needed (priority order):**

1. **FD-026**: Goal Beacon — Level end trigger (HIGH priority)
2. **FD-025**: Tube Connector — Level connectivity
3. **FD-027**: Spawn Cinematic — Player introduction
4. **FD-021**: Scene Transition — Seamless area transitions

**Verification commands:**
```bash
# Test VCamera intro
./runtest.sh --oys core_v2/scripts/intro

# Test determinism
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd

# Test props
./runtest.sh --oys TestScenePropZoo

# UI capture
./test_ui.sh --scene=DebugOverlay --base64
```
