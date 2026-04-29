# Terminal Integration Guide

## Overview

This document describes how terminals (HoloTerminalV2) integrate with the circuit system and other components.

## Architecture

```
HoloTerminalV2 (1005 lines → refactored)
    │
    ├── InteractableBaseV2 (base)
    │   └── slide animation, state management
    │
    ├── TerminalCameraRig (NEW - extracted)
    │   └── cinematic/focus camera modes
    │
    ├── TerminalHUDBridge (NEW - extracted)
    │   └── HUD attachment logic
    │
    ├── TerminalUI
    │   └── cursor, UI interaction
    │
    └── CircuitTerminalBridge (NEW)
        └── Terminal → circuit connection
```

## Extracted Components

### TerminalCameraRig

Manages cinematic camera and focus mode transitions.

```gdscript
var rig = TerminalCameraRig.new()
rig.use_cinematic_zone = true
rig.allow_focus_mode = true
rig.cinematic_camera_behavior = 0  # CAMERA_FIXED
add_child(rig)
rig.initialize(terminal_node)
```

**API:**
```gdscript
rig.enter_focus_mode()
rig.exit_focus_mode()
rig.toggle_focus_mode()
rig.is_focused() -> bool
rig.is_player_in_zone() -> bool
```

**Signals:**
- `focus_entered` - Player entered focus mode
- `focus_exited` - Player exited focus mode

### TerminalHUDBridge

Manages HUD attachment for helmet-mounted displays.

```gdscript
var hud_bridge = TerminalHUDBridge.new()
hud_bridge.attach_to_active_camera = true
hud_bridge.hud_screen_scale = 0.45
hud_bridge.hud_interaction_radius = 3.0
add_child(hud_bridge)
hud_bridge.initialize(terminal_node)
```

**API:**
```gdscript
hud_bridge.attach_hud()
hud_bridge.detach_hud()
hud_bridge.is_hud_attached() -> bool
hud_bridge.set_suspended(suspended: bool)
hud_bridge.is_player_within_hud_radius() -> bool
```

**Signals:**
- `hud_attached` - HUD successfully attached
- `hud_detached` - HUD successfully detached

## Circuit Integration

### CircuitTerminalBridge

Bidirectional bridge between terminal and circuit system.

```gdscript
var bridge = CircuitTerminalBridge.new()
bridge.circuit_manager_path = NodePath("/root/LogicCircuitManager")
bridge.terminal_node_id = "terminal_1"
bridge.output_node_id = "door_main"
bridge.auto_connect = true
add_child(bridge)
```

**API:**
```gdscript
# Connect terminal output to circuit input
bridge.connect_output("terminal_1", "door_main")

# Send commands from terminal to circuit
bridge.send_terminal_command("activate")
bridge.send_terminal_command("deactivate")
bridge.send_terminal_command("toggle")

# Send value directly
bridge.send_to_circuit(true)

# Snapshot for replay determinism
var snapshot = bridge.get_snapshot()
bridge.restore_snapshot(snapshot)
```

### CircuitUINode

For UI controls that need circuit connection.

```gdscript
var circuit_ui = CircuitUINode.new()
circuit_ui.circuit_manager_path = NodePath("/root/LogicCircuitManager")
circuit_ui.node_id = "button_1"
circuit_ui.auto_connect = true
add_child(circuit_ui)

# Button pressed → circuit signal
circuit_ui.send_output(true)
```

## HoloTerminalV2 Refactoring

HoloTerminalV2 can now optionally use extracted components:

```gdscript
# In .tscn or .gd
export(bool) var use_extracted_camera_rig = false
export(bool) var use_extracted_hud_bridge = false
```

When enabled, the terminal initializes the components internally:
```gdscript
# In _ready():
if use_extracted_camera_rig:
    _initialize_camera_rig_component()
if use_extracted_hud_bridge:
    _initialize_hud_bridge_component()
```

**Benefits:**
- Cleaner terminal code (reduced from 1005 to ~350 lines with components)
- Reusable camera rig across multiple terminals
- Reusable HUD bridge for different HUD configurations
- Easier testing of individual components

## Input Flow

```
Player Input
    │
    ├── HoloTerminalV2._input()
    │   ├── Focus toggle → enter_focus_mode() / exit_focus_mode()
    │   └── Mouse/Keyboard → viewport input bridge
    │
    ├── TerminalUI.process_mouse_click()
    │   └── _inject_mouse_button() → UI controls
    │
    └── (Optional) CircuitTerminalBridge
        └── send_to_circuit() → LogicCircuitManager
```

## Replay Determinism

All components implement snapshot system:

```gdscript
# InteractableBaseV2
func get_snapshot() -> Dictionary:
    return {
        "active": is_active,
        "used": is_used,
        "progress": anim_progress,
        "target": target_progress
    }

# TerminalCameraRig
func get_snapshot() -> Dictionary:
    return {
        "focused": _is_focused,
        "player_in_zone": _player_in_zone
    }

# CircuitTerminalBridge
func get_snapshot() -> Dictionary:
    return {
        "connected": _is_connected,
        "pending": pending_commands
    }
```

## Example: Door Control from Terminal

1. Create CircuitGraphResource with nodes:
   - `terminal_button`: type="PROP", scene_path=NodePath(...)
   - `door_main`: type="PROP", scene_path=NodePath(Doors/MainDoor)

2. Connect in graph:
   ```gdscript
   graph.connect_nodes("terminal_button", 0, "door_main", 0, "WIRED")
   ```

3. In terminal scene, add CircuitTerminalBridge:
   ```gdscript
   var bridge = CircuitTerminalBridge.new()
   bridge.output_node_id = "door_main"
   ```

4. When terminal button clicked:
   ```gdscript
   bridge.send_terminal_command("activate")
   # or
   bridge.send_to_circuit(true)
   ```

## Testing

```bash
./runtest.sh --oys test_terminal
./runtest.sh -a ./core_v2/tests/test_terminal_circuit_bridge.gd
```