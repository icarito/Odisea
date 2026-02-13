Spec: Unified Interaction Framework (UIF) - Sensor-Based - Odisea Core_v2

1. Architectural Concept

The interaction system shifts from a precise RayCast ("pixel hunting") to a Volume-Based Detection (Sensor). The player projects an invisible volume (Box/Cone) forward. Any InteractableEntity within this volume becomes a "Candidate". The system evaluates candidates each frame to determine the best "Focus Target" based on proximity and angle.

This unifies interaction logic for static objects (terminals) and dynamic objects (moving platforms, pushable boxes), ensuring all gameplay elements respect the deterministic step(dt) cycle.

2. Component Architecture

A. The Sensor (InteractionSensor.gd)

Location: core/Components/Player/InteractionSensor.gd
Node: Area (Child of PlayerController).
Responsibilities:

Candidate Tracking: Maintain a list of overlapping Interactable objects.

Evaluation Loop (Step): In every step(dt), calculate a "Score" for each candidate:

Angle: Dot product with camera forward vector (Center is better).

Distance: Closer is better.

Line of Sight: Internal RayCast check to prevent interaction through walls.

Focus Management: Emit signals when the "Best Candidate" changes.

B. The Interactable (InteractableEntity.gd)

Location: core/Components/Shared/InteractableEntity.gd
Inheritance: Base class for all interactive objects.
Core Data:

interaction_text: String ("Open", "Push", "Activate").

interaction_point: Position3D (Optional center for LoS checks).

requirements: AttributeResource (e.g., "Strength > 5").

3. Integration with Existing Features ("The Zoo")

The goal is to refactor current prototypes (MovingPlatform, Conveyor, Drawer) into this unified system.

A. Moving Platforms (MovingPlatform)

Current Status: Deterministic KinematicBody with time_accumulator.

UIF Integration: Add an InteractableEntity child node if the platform has a control panel (e.g., an elevator button). The button is the interactable, not the platform itself.

B. Conveyor Belts (Conveyor)

Current Status: Physics area applying force.

UIF Integration: Generally passive. However, a "Conveyor Switch" object would be an InteractableEntity that toggles the Conveyor.active state deterministically.

C. Pushable Boxes (PushableBox)

Current Status: Hybrid Rigid/Kinematic body.

