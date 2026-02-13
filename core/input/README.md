# Input Architecture V2

This directory contains the core input system for the game, designed to be **deterministic**, **replay-friendly**, and **input-agnostic**.

## Core Components

### 1. `InputProvider.gd`
The bridge between the hardware (Godot's `Input` singleton) and the game logic.
- **Responsibility**: capturing the state of input devices (keyboard, mouse, gamepad) every frame.
- **Live Mode**: Reads directly from `Input`.
- **Replay Mode**: Reads from a pre-recorded buffer.
- **Gamepads**: Currently hardcoded to Device 0. Right stick maps to camera look.

### 2. `InputData.gd`
A pure data container (struct) that represents inputs for a single frame.
- **Fields**: `move_vec`, `jump`, `sprint`, `mouse_delta`.
- **Serialization**: Can be converted to/from Dictionary/JSON for replays.

## Integration

The `PlayerController` owns an `InputProvider`.
In `_physics_process`:
1. Player calls `provider.get_input()`.
2. Provider checks strictly current hardware state (or replay buffer).
3. Player passes `InputData` to its `step(dt, input)` method.

## Joystick & Gamepad Support

- **Movement (Left Stick)**: Computed via Godot's Input Maps (`move_left`, `move_right`, etc). You must map Joystick axes 0/1 to these actions in Project Settings.
- **Camera (Right Stick)**: Computed manually in `InputProvider` by reading `JOY_AXIS_2` (X) and `JOY_AXIS_3` (Y).
- **Deadzone**: A hardcoded constant `JOY_DEADZONE` (0.2) is applied.

## Future: Local Multiplayer

To support multiple local players:
1. Instantiate multiple `InputProvider` instances.
2. Add a `device_id` property to `InputProvider`.
3. Update `Input.get_joy_axis(device_id, ...)` calls to use this dynamic ID.
4. Assign each provider to a different `PlayerController`.
