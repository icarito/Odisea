Feature Specification: 2.5D Side-Scroller Mode Transition

1.0 Overview & Strategic Goals

This document specifies the implementation of a seamless, automatic transition system between the standard 3D third-person exploration mode and a constrained 2.5D side-scrolling platforming mode. This feature is designed to provide level designers with a tool to create focused, classic platforming challenges. Implementation must adhere with absolute strictness to the project's existing deterministic, "pure input replay" architecture. Every new state variable introduced by this system must be fully integrated into the snapshot and replay framework to ensure perfect replay and session restoration fidelity.

The primary goals and success metrics for this feature are detailed below:

Goal	Key Success Metric
Fluid Gameplay Transition	The shift in controls and camera perspective must feel intuitive and polished. Player feedback should indicate the transition is a natural part of the gameplay, not a jarring interruption.
Deterministic Purity	When playing back a replay that includes a 2.5D section, the final player state must exhibit a divergence of less than the established 0.0001 unit tolerance compared to the originally recorded session.
Design Flexibility	Level designers can easily place and configure SideScrollTransitionZone instances with minimal effort. The feature will be robust enough to serve as the "twist" (ten) in the kishōtenketsu level design philosophy.

This specification will now detail the core architectural components and data flow required to achieve these goals.

2.0 Core System Architecture & Data Flow

A clear architectural plan is critical to ensure this feature integrates cleanly with existing systems without compromising stability or determinism. This section outlines the high-level interactions between established components like PlayerControllerV2 and ReplayManager, and the new components required for the 2.5D mode transition.

The event and data flow upon the player character entering a SideScrollTransitionZone will proceed as follows:

1. Detection: A SideScrollTransitionZone, implemented as an Area3D node, detects the player character's body_entered signal.
2. State Update: The zone emits a signal to the ReplayManager singleton, which then updates the global player state. This signal includes the specific Transform of the 2.5D plane. This state change must be captured as a discrete event in the replay stream to ensure it is reproduced deterministically.
3. Controller Constraint: The PlayerControllerV2.step() function, which reads the player's state each frame, detects the new is_in_25d_mode flag. It then deliberately ignores any depth-axis input from the input object and constrains all physics calculations to the newly defined 2.5D plane.
4. Camera Transition: The PlayerSpringCam script, also listening for the global state change, is notified. It calculates a target side-scroller transform and begins a smooth, time-based interpolation from its current 3D position to the new fixed perspective.
5. Snapshot Integration: At every frame, the SessionManager's snapshotting process queries the player's state. It queries, serializes, and stores the new data fields essential for this feature: is_in_25d_mode, camera_transition_alpha, and the active_2d_plane_transform.

This event-driven approach is critical for maintaining determinism and simplifying unit testing. It ensures the core PlayerControllerV2 remains pure, reacting only to state changes managed by singletons. This avoids the "marioneta basada en estados" (state-based puppeteering) anti-pattern identified during previous replay system analysis, where physics are incorrectly overwritten frame-by-frame, and instead adheres to our established 'pure input replay' architecture.

3.0 Component Implementation Details

3.1 SideScrollTransitionZone

This component serves as the catalyst for the entire feature. It will be implemented as a self-contained, reusable Godot scene that level designers can easily place, scale, and configure within their levels to define the boundaries of a side-scrolling section.

* Node Type: The SideScrollTransitionZone will be a standalone scene whose root node is an Area3D.
* Configuration: The scene's script will expose export variables for editor customization. The primary configuration will be a Transform variable that defines the origin and orientation of the 2D plane of movement. This allows designers to create horizontal, vertical, or even diagonally oriented side-scrolling sections.
* Logic: The script will connect to its own body_entered and body_exited signals.
  * On body_entered, it will call ReplayManager.enter_25d_zone(plane_transform) to broadcast the state change globally.
  * On body_exited, it will call the corresponding ReplayManager.exit_25d_zone() method to revert the player and camera back to the standard 3D mode.

3.2 PlayerControllerV2 Modifications

All modifications to the core PlayerControllerV2 will be minimal and non-invasive to protect its deterministic integrity. The changes will be focused entirely on reacting to a new state read from the snapshot, not on adding new complex logic or environmental detection.

* New State Variables: Expand the player's state Dictionary to include is_in_25d_mode (a bool) and active_2d_plane (a Transform).
* Input Handling: Within the step() function, the existing input processing logic will be wrapped in a conditional check. If is_in_25d_mode is true, the component of the input vector corresponding to the plane's local Z-axis (depth) will be zeroed out.
* Physics Constraint: After calculating the intended velocity for the frame but before calling move_and_slide(), the final velocity vector will be projected onto the active_2d_plane. This mathematical operation effectively removes any motion perpendicular to the plane, ensuring the player character remains perfectly "on the rail."

3.3 PlayerSpringCam Update

The camera's behavior is the most prominent visual indicator of the mode transition, and its smoothness is paramount to a high-quality player experience. The logic must be fully deterministic and restorable from a snapshot at any point.

* State Listener: The PlayerSpringCam.gd script will listen for the same global state change event that the player controller responds to.
* Target Calculation: Upon entering 2.5D mode, the camera will compute its target transform. The target position will be a fixed offset from the player's position along the normal of the active_2d_plane. Its rotation will be fixed to look perpendicularly at the plane, creating the classic side-scroller view.
* Smooth Transition: The camera will perform a non-physics-based interpolation (using lerp() for position and slerp() for rotation) from its current 3D orbital transform to the target side-scroller transform. This transition must be driven by a fixed frame counter or a physics-tick-based timer, explicitly avoiding the use of delta to guarantee deterministic playback. The progress of this interpolation, a float from 0.0 to 1.0 named camera_transition_alpha, must be stored in the game state.
* Tracking in 2.5D: Once the transition is complete (camera_transition_alpha = 1.0), the camera's update logic will be simplified. It will directly follow the player's position projected onto the plane, maintaining its fixed offset and rotation.

3.4 Replay & Snapshot System Integration

