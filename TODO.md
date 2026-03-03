# TODO — MVP Odisea (2026-03-02)

## First Level Priority (FD System)

See `docs/features/FEATURE_INDEX.md` for full tracking.

### Critical Path to MVP (What's Left)

1. **FD-026**: Goal Beacon — Level end trigger
2. **FD-025**: Tube Connector — Level connectivity  
3. **FD-027**: Spawn Cinematic / ScreenBorders
4. **FD-021**: Scene Transition System

### Known Issues (from last stress test)

1. **OYS Gravity Anomaly**: Scripts inject downward force anomaly. Review SessionManager integration with physics when input comes from OYS buffer.

2. **Slope Handling**: Character gets stuck or doesn't climb ramps. Verify `floor_max_angle` in controller.

3. **Movement Resistance**: Excessive friction/weight feeling. Review velocity Lerp calculations.

### Already Implemented (Verified)

- ✓ WindZone (`IndustrialFan.gd`, `WindTunnelV2.gd`)
- ✓ Guardrail Platform (`scenes/common/GuardrailSegment.tscn`)
- ✓ VCamera Integration (`core_v2/camera/VCameraSystemRig.gd`)
- ✓ HoloTerminal Cinematic (`core_v2/props/HoloTerminalV2.tscn`)
- ✓ Subtitles (`core_v2/ui/retro/SubtitlesOverlay.tscn`)
- ✓ Emitter/Destroyer Areas

### Active Features (In Progress)

- **FD-019**: Multiplayer Split-screen
- **FD-020**: WallManager Area
- **FD-021**: Scene Transition System (Design)

## References

- Feature tracking: `docs/features/FEATURE_INDEX.md`
- Feature specs: `docs/features/`
- Archive: `docs/features/archive/`
- Normas: `AGENTS.md`
