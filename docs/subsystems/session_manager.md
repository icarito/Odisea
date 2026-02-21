# Session Manager

**Source:** `core_v2/autoloads/SessionManager.gd`

The `SessionManager` is the heart of the project's deterministic simulation and replay system. It orchestrates the game loop, input recording, and replay verification.

## Key Responsibilities

### 1. Replay Recording and Playback
It manages the state of recording (during gameplay) and replaying (for validation/regression tests).

-   **Recording:** Captures input from the `InputProviderV2` at a fixed rate (60 Hz) and stores it in a buffer.
-   **Replaying:** Feeds stored input back into the `InputProviderV2` and validates the resulting state.
-   **Ghost System:** Integrates with `GhostManager` to visualize recorded replays alongside live gameplay.

### 2. Deterministic Execution
To ensure replays are deterministic across machines and runs:
-   **Fixed Update:** Uses a custom `step(dt)` function called from `_physics_process`.
-   **Centralized Stepping:** Instead of relying on Godot's internal `_physics_process` order (which can be nondeterministic), `SessionManager` explicitly calls `step()` on:
    -   The Player (`PlayerControllerV2`)
    -   Active Platforms/Props (via `replay_sync` group)
    -   Cinematic Manager
-   **Input Injection:** Directly injects input data into the simulation step.

### 3. Odyssey Script (OYS) Integration
It acts as the host for the `OYS_Interpreter`, executing script commands like `move`, `wait`, `assert`, and `spawn`.

### 4. Teleport System
Manages seamless player teleportation and initial spawning, ensuring camera and physics state are reset correctly.

## Drift Validation
At the end of a replay, `SessionManager` compares the final player state (position, rotation) against the expected state stored in the replay file.
-   **Thresholds:** Validates against a strict tolerance (e.g., 0.01 units).
-   **Reporting:** Prints detailed drift metrics (position diff, yaw diff) and fails the test if thresholds are exceeded.

## Usage in Tests

The `SessionManager` is heavily used by the test runner (`tests/debug_runner.gd` and `conftest.py`) to execute `.oys` scripts and validate game logic.

```gdscript
# Example: Load and play a replay file
SessionManager.load_and_play("res://tests/replays/test_jump.oys")
```
