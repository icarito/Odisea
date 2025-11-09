# Touch Controls for Mobile/Tablet

This project includes touch controls for mobile and tablet devices using the Virtual Joystick addon from the Godot Asset Library.

## Features

- **Left Joystick**: Controls player movement (forward, back, left, right)
- **Right Joystick**: Controls camera rotation (look around)
- **Action Buttons**: 
  - Jump button (↑)
  - Interact button (F)
  - Sprint button (⚡)
  - Crouch button (↓)

## Visibility

The touch controls are automatically shown only on devices with touchscreens and hidden on desktop. For desktop testing, the controls can be used with mouse input thanks to the `emulate_touch_from_mouse` setting.

## How to Add Touch Controls to a Scene

The touch controls are implemented as a reusable scene (`scenes/touch_controls.tscn`) that can be added as a child to any `CogitoPlayer` instance:

1. Open your scene in the Godot editor
2. Find the `CogitoPlayer` node
3. Add a child node by instancing `res://scenes/touch_controls.tscn`
4. The touch controls will automatically:
   - Find the player's camera/head nodes
   - Show/hide based on device type
   - Connect to the player's input system

## Configuration

You can adjust the camera sensitivity by modifying the `camera_sensitivity` export variable in the TouchControls node (default: 2.0).

## Implementation Details

- **Addon**: Virtual Joystick from https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot
- **Plugin Location**: `addons/virtual_joystick/`
- **Touch Controls Scene**: `scenes/touch_controls.tscn`
- **Touch Controls Script**: `scenes/scripts/touch_controls.gd`

### How It Works

- The left joystick uses input actions (`forward`, `back`, `left`, `right`) that are already configured in the project
- The right joystick directly manipulates the player's neck and head nodes for camera rotation
- Action buttons use `TouchScreenButton` nodes that emit standard input actions
- All controls automatically show/hide based on `DisplayServer.is_touchscreen_available()`

## Project Settings

The following settings have been configured in `project.godot`:

```gdscript
[input_devices]
pointing/emulate_touch_from_mouse=true
pointing/emulate_mouse_from_touch=false
```

These settings are required by the Virtual Joystick addon and enable testing with mouse input on desktop.

## Example Scene

The main scene (`scenes/ether.tscn`) includes touch controls as a reference implementation. Check the `CogitoPlayer/TouchControls` node in that scene.
