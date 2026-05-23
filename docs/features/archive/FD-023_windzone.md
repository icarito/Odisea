# FD-023: WindZone

**Status:** Complete
**Priority:** High
**Effort:** Medium
**Created:** 2026-03-02
**Completed:** 2026-03-02

## Implementation

WindZone already exists in two forms:

1. **IndustrialFan** (`core_v2/props/IndustrialFan.gd`)
   - Prop that pushes objects in its forward direction (-Z)
   - Uses `set_external_velocity()` for PlayerControllerV2
   - Uses `apply_central_impulse()` for RigidBody

2. **WindTunnelV2** (`core_v2/components/WindTunnelV2.gd`)
   - Reusable Area component
   - Configurable `wind_velocity` Vector3
   - Has snapshot support for deterministic replay
   - Uses `set_external_source_is_static(false)` to act like a flow field

## Files

- `core_v2/props/IndustrialFan.gd`
- `core_v2/props/IndustrialFan.tscn`
- `core_v2/components/WindTunnelV2.gd`
- `core_v2/props/VentilationTurbine.tscn` (uses WindTunnelV2)

## Usage

```gdscript
# IndustrialFan: Place in scene, activates with is_active
# WindTunnelV2: Add Area node with WindTunnelV2.gd script
```
