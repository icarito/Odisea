Technical Specification: Deterministic Interactable System (Odisea V2)

1. Objective

Create a base framework for objects that toggle states (Open/Closed, On/Off, Active/Inactive) through player interaction. The system must ensure 100% mathematical determinism for replay integrity, inspired by the state-logic of Cogito but optimized for Odisea's snapshot architecture.

2. Core Architecture

A. InteractableBaseV2.gd (Abstract Class)

Inherits from KinematicBody (preferred for floor velocity inheritance) or Spatial.

State Variables:

is_active: bool: The logical state (e.g., true = open/on, false = closed/off).

anim_progress: float: Normalized value (0.0 to 1.0) representing the current visual position.

target_progress: float: The goal state (usually 1.0 or 0.0).

anim_speed: float: Progress increment per second (1.0 / duration).

Core Methods:

interact(): Toggles is_active and sets the target_progress.

step(dt): Calculated during the fixed physics step. Updates anim_progress towards target_progress and calls _update_visuals().

3. Implementation Types

1. Sliding Door / Drawers (SlidingObjectV2)

Similar to Cogito_Door.gd but using relative translation.

Logic: translation = start_pos.linear_interpolate(start_pos + slide_vector, _ease(anim_progress)).

Generalization: Drawers are simply sliding objects with a restricted axis and specific sound triggers.

2. Rotational Levers / Valves (RotatingObjectV2)

Logic: Applies lerp to a specific axis of rotation.

Reference: Mimics Cogito_Switch.gd mechanics for flipping states via angular displacement.

3. Push Buttons / Consoles (ButtonV2)

Logic: Combines a short Z-axis displacement with material emission changes.

Feedback: material.emission_energy = lerp(min_e, max_e, anim_progress).

4. Replay & Determinism (The Odisea Contract)

Unlike Cogito's reliance on standard AnimationPlayers (which can drift if not synced to physics), Odisea objects calculate their state based on a time_accumulator or a fixed-step increment.

func get_snapshot() -> Dictionary:
    return {
        "active": is_active,
        "progress": anim_progress,
        "target": target_progress
    }

func restore_snapshot(data: Dictionary):
    is_active = data.active
    anim_progress = data.progress
    target_progress = data.target
    _update_visuals(0) # Immediate visual snap


5. Interaction System (InteractionRayV2)

The PlayerControllerV2 uses a RayCast to detect interactables:

Detection: Checks if the collided object is in the interactable group.

UI Feedback: Reads object.interaction_text to display on the HUD (e.g., "Pull Lever", "Open Drawer").

Execution: On input action ("E"), calls object.interact().

6. Sound & Visual Polish

Synchronized Audio: Sounds are triggered within step(dt) when anim_progress hits thresholds (0.0 or 1.0) to ensure audio-visual sync during replays.

Visual Tilt (Optional): Objects can implement the "Visual Tilt" logic from PushableBoxV2 if they are meant to feel loose or mechanical.

7. Comparison with Cogito

Cogito: Focuses on ease of use via Editor properties and Signal-based logic.

Odisea V2: Focuses on State Persistence. While Cogito objects might reset or desync in a complex replay, Odisea objects are treated as "Physics-calculated" entities that always match the time_accumulator.