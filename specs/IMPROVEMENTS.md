# OYS (Odyssey Script) & Physics Integration Improvements

## Overview
This document outlines critical improvements for the integration of OYS with the core physics system, specifically addressing gravity application during scripted sequences and robustness of slope handling.

## Spec 1: OYS Physics State Override & Gravity Normalization

### Problem
During OYS execution (commands `WAIT`, `FW`), an anomalous downward force (gravity accumulation) is observed. The player character either falls faster than expected or fails to maintain height when traversing flat surfaces or moving platforms under script control. This suggests a disconnect between the `SessionManager` input injection and the `PlayerController`'s physics state management.

### Proposed Solution
Implement a **Physics Override State** in `PlayerController` that is explicitly managed by the `InputProvider` when in "Scripted Mode".

### Technical Requirements
1.  **InputProvider Expansion**: Add a `is_scripted_sequence` flag to `InputData`.
2.  **Gravity Reset**: When `is_scripted_sequence` is true, `PlayerController` must:
    *   Reset vertical velocity (`velocity.y`) to 0 if `is_on_floor()` is true at the start of the frame.
    *   Apply a constant, non-accumulating "snap" gravity (e.g., `-1.0`) instead of standard gravity (`-9.8 * delta` accumulation) to keep the character grounded without building up excessive downward momentum.
3.  **State Transition**: Ensure seamless transition back to normal physics when script ends.
    *   On script end, reset `velocity.y` to 0 if grounded.
    *   Retain horizontal velocity if the script ends while moving (optional, for momentum).

### Validation Plan
*   Create a test case `test_oys_gravity.oys`:
    *   `SPAWN scene="res://core/levels/TestScene.tscn" pos=[0, 10, 0]`
    *   `WAIT 1.0` (Allow settling)
    *   `ASSERT is_on_floor`
    *   `FW 2.0` (Move forward for 2 seconds)
    *   `ASSERT is_on_floor` (Must remain grounded)
    *   `ASSERT velocity.y > -2.0` (Check for excessive gravity accumulation)

## Spec 2: Robust Slope Handling & Ground Snap

### Problem
The current implementation of "snap" and slope handling causes the character to get stuck on ramps or jitter when moving down slopes. This is likely due to `move_and_slide_with_snap` parameters or incorrect vector projection on steep surfaces.

### Proposed Solution
Refactor `PlayerMovement` to use an explicit **Slope Normal Projection** and a dedicated **Snap State Machine**.

### Technical Requirements
1.  **Slope Projection**:
    *   Calculate the movement vector parallel to the floor normal: `motion = motion.slide(floor_normal)`.
    *   Ensure this projection is applied *before* `move_and_slide`.
2.  **Dynamic Snap Vector**:
    *   Use a larger snap vector (e.g., `Vector3.DOWN * 0.5`) when `is_on_floor()` is true.
    *   Disable snap (set to `Vector3.ZERO`) immediately when `jump` is pressed.
3.  **Max Floor Angle**:
    *   Expose `floor_max_angle` as an export variable (default 45 degrees).
    *   If `floor_angle > max_angle`, treat as wall (disable snap, apply sliding gravity).

### Validation Plan
*   Create `test_slope_movement.oys`:
    *   Spawn player at bottom of a 30-degree ramp.
    *   `FW 2.0` (Move up).
    *   `ASSERT position.y > initial_y` (Confirm ascent).
    *   `ASSERT is_on_floor`.
    *   Spawn player at top of ramp.
    *   `FW 2.0` (Move down).
    *   `ASSERT is_on_floor` (Confirm no airborne state while descending).
