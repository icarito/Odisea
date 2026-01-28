Spec: Unified Interaction Framework (UIF) - Sensor-Based - Odisea Core_v2

1. Architectural Concept

The interaction system shifts from a precise RayCast ("pixel hunting") to a Volume-Based Detection (Sensor). The player projects an invisible volume (Box/Cone) forward. Any InteractableEntity within this volume becomes a "Candidate". The system evaluates candidates each frame to determine the best "Focus Target" based on proximity and angle.

This unifies interaction logic for static objects (terminals) and dynamic objects (moving platforms, pushable boxes), ensuring all gameplay elements respect the deterministic step(dt) cycle.

2. Component Architecture

A. The Sensor (InteractionSensor.gd)

Location: core_v2/Components/Player/InteractionSensor.gd
Node: Area (Child of PlayerControllerV2).
Responsibilities:

Candidate Tracking: Maintain a list of overlapping Interactable objects.

Evaluation Loop (Step): In every step(dt), calculate a "Score" for each candidate:

Angle: Dot product with camera forward vector (Center is better).

Distance: Closer is better.

Line of Sight: Internal RayCast check to prevent interaction through walls.

Focus Management: Emit signals when the "Best Candidate" changes.

B. The Interactable (InteractableEntity.gd)

Location: core_v2/Components/Shared/InteractableEntity.gd
Inheritance: Base class for all interactive objects.
Core Data:

interaction_text: String ("Open", "Push", "Activate").

interaction_point: Position3D (Optional center for LoS checks).

requirements: AttributeResource (e.g., "Strength > 5").

3. Integration with Existing Features ("The Zoo")

The goal is to refactor current prototypes (MovingPlatform, Conveyor, Drawer) into this unified system.

A. Moving Platforms (MovingPlatformV2)

Current Status: Deterministic KinematicBody with time_accumulator.

UIF Integration: Add an InteractableEntity child node if the platform has a control panel (e.g., an elevator button). The button is the interactable, not the platform itself.

B. Conveyor Belts (Conveyor)

Current Status: Physics area applying force.

UIF Integration: Generally passive. However, a "Conveyor Switch" object would be an InteractableEntity that toggles the Conveyor.active state deterministically.

C. Pushable Boxes (PushableBoxV2)

Current Status: Hybrid Rigid/Kinematic body.

UIF Integration: The box itself is an InteractableEntity with interaction_text = "Push".

Logic: Instead of a simple "press E", the interaction could be "Hold E to Grab", changing the Player's state to PUSHING and locking movement to the box's axis.

D. Legacy Objects Refactor (Doors, Drawers, Levers)

Current scripts using Tween or AnimationPlayer must be converted to step(dt) logic:

SlidingObjectV2 (Doors/Drawers): pos = lerp(start, end, progress). Progress advances in step(dt).

RotatingObjectV2 (Levers/Valves): rot = lerp(start_angle, end_angle, progress).

4. Standardized Signal Protocol

Sensor -> UI:

signal focus_changed(new_interactable): Updates HUD prompt.

Interactable -> Object Logic:

signal interacted(player): Executes the action.

signal interaction_denied(reason): Feedback for locked/failed attempts.

5. "The Interaction Zoo" (Test Scene)

A new scene core_v2/scenes/InteractionZoo.tscn will serve as the validation ground for all InteractableEntity types.

Exhibits:

The Airlock: A SlidingDoorV2 controlled by a Keypad (Interactable) requiring Security Level 1.

The Warehouse: A PushableBoxV2 on a Conveyor controlled by a LeverV2.

The Archive: A desk with DrawerV2 objects containing items.

The Elevator: A MovingPlatformV2 triggered by a PressurePlateV2 (Sensor-based logic).

6. Implementation Roadmap

Base Classes: Create InteractableEntity.gd and InteractionSensor.gd.

Refactor Door: Convert the existing door prototype to SlidingDoorV2 using the new base class.

Zoo Construction: Build the test scene and verify that SessionManager correctly records and replays interactions with all object types.