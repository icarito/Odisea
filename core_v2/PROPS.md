# Prop Contract Documentation

This document describes the contract for creating props in the Odisea Game project.

## Overview

Props are interactive or animated game objects that extend from `InteractableBaseV2` or `PropBaseV2`. They can be tested using the `test_prop.sh` pipeline.

## Base Classes

### InteractableBaseV2 (core_v2/components/InteractableBaseV2.gd)

Base class for all interactive objects.

**Key Properties:**
- `is_active: bool` - Current state of the prop
- `anim_progress: float` - Animation progress (0.0 to 1.0)
- `anim_speed: float` - Speed of animation (default 1.0)
- `anim_duration: float` - Duration of one animation cycle in seconds (default 1.0)

**Key Methods:**
- `_ready()` - Called when node enters scene
- `_physics_process(delta)` - Called every physics frame, updates animation
- `step(delta)` - Advances animation by delta time
- `_update_visuals()` - Override to update visual appearance based on `anim_progress`
- `interact()` - Override to handle player interaction

### PropBaseV2 (core_v2/components/PropBaseV2.gd)

Extends `InteractableBaseV2` with additional prop-specific functionality.

## Creating a New Prop

### 1. Create the Script

```gdscript
extends PropBaseV2

# Export variables for editor tweaking
export var my_property: float = 1.0

func _ready():
    # Call parent _ready() to ensure proper initialization
    ._ready()
    # Your initialization code here

func _update_visuals():
    # Map anim_progress (0.0-1.0) to visual properties
    var t = anim_progress
    
    # Example: interpolate color
    var mesh_inst = get_node_or_null("MeshInstance")
    if mesh_inst:
        var mat = SpatialMaterial.new()
        mat.albedo_color = Color.BLACK.linear_interpolate(Color.GREEN, t)
        mat.emission_enabled = t > 0.5
        mat.emission = Color.GREEN
        mat.emission_energy = t * 2.0
        mesh_inst.material_override = mat

func interact():
    # Toggle state
    is_active = not is_active
    # Animation will be handled by step() in _physics_process
```

### 2. Create the Scene (.tscn)

1. Create a new Scene with your script as root
2. Add visual elements (MeshInstance, Particles, etc.)
3. Add collision shapes if needed
4. Save as `.tscn` file

### 3. Create Test Script (.oys)

```oys
# Test script for MyProp
# This runs in the test_prop.sh pipeline

load_scene("res://core_v2/props/MyProp.tscn")

# Wait for prop to initialize
wait(0.5)

# Capture idle state
screenshot("idle")

# Interact to toggle state
interact()

# Wait for transition
wait(0.5)

# Capture active state
screenshot("active")

# Toggle back
interact()
wait(0.5)
screenshot("off")
```

## Animation System

The animation system works as follows:

1. **`_physics_process(delta)`** calls **`step(delta)`**
2. **`step(delta)`** updates `anim_progress` based on `is_active` and `anim_speed`
3. **`_update_visuals()`** is called every frame with the current `anim_progress`

### Animation Behavior

- When `is_active` changes to `true`: `anim_progress` goes from 0.0 → 1.0
- When `is_active` changes to `false`: `anim_progress` goes from 1.0 → 0.0
- Use `anim_speed` to control animation speed (default 1.0)
- Override `_update_visuals()` to map `anim_progress` to visual properties

## Testing Props

### Using test_prop.sh

```bash
# Test a specific prop
./test_prop.sh --target="MyProp" --base64

# This will:
# 1. Find MyProp.tscn and MyProp.oys
# 2. Run the test in Godot headless
# 3. Capture screenshots at each stage
# 4. Compare pixel differences to detect visual changes
```

### Test Output

Tests generate screenshots in `test_output/ui/`:
- `propstage_0_idle.png` - Initial state
- `propstage_1_transitioning.png` - During transition
- `propstage_2_active.png` - Active state
- `propstage_3_transitioning_off.png` - Transitioning off
- `propstage_4_off.png` - Off state

### Validation Criteria

The test passes if:
- Delta between idle and active ≥ 0.5% pixels changed
- No runtime errors

## Energy Visualization Tips

For props that show energy/power states:

1. **Inactive State**: Use dark colors (near black: `Color(0.05, 0.05, 0.05)`)
2. **Active State**: Use bright colors with emission (`Color(0.0, 1.0, 0.8)`)
3. **Always create new materials**: Don't modify shared materials
4. **Use emission**: Set `emission_enabled = true` and `emission_energy` for glow effects
5. **Consider pulse effects**: Add time-based variation for active state

Example from CircuitCable:
```gdscript
var inactive_color = Color(0.1, 0.1, 0.1)  # Almost black
var active_color = Color(0.0, 1.0, 0.8)     # Bright cyan

var mat = SpatialMaterial.new()
mat.albedo_color = inactive_color.linear_interpolate(active_color, t)
mat.emission_enabled = true
mat.emission = current_color
mat.emission_energy = t * 5.0  # Strong glow
```

## Examples

See these props for reference:
- `core_v2/props/CircuitCable.tscn` / `core_v2/systems/circuit/CircuitCable.gd` - Energy cable
- `core_v2/props/CircuitExample.tscn` / `core_v2/props/CircuitExampleProp.gd` - Example prop
- `core_v2/props/scifi_lights/EmergencyBeaconV2.gd` - Light prop
