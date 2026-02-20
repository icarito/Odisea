Technical Specification: HoloTerminal V2.2 (Cinematic Integration)
1. Objective

Upgrade the HoloTerminalV2 to include an integrated Cinematic Camera System. The terminal should automatically capture the player's camera view when activated and entered, providing a clear view of the UI. Additionally, it must manage the visibility of the holographic mesh to prevent visual obstruction during the close-up shot.
2. Architecture Updates
A. New Node Hierarchy

We will extend the existing HoloTerminalV2.tscn to include the camera infrastructure as children. This keeps the prefab self-contained.

HoloTerminalV2 (InteractableBaseV2)
├── BaseMesh
├── ScreenContainer
│   └── ScreenMesh (The "Halo"/Hologram Volume)
├── Viewport
├── TerminalUI
├── InteractableEntity (Trigger for E key)
├── CollisionShape
│
└── CinematicSetup (Spatial) - [NEW CONTAINER]
    ├── TerminalCamRig (CinematicRig/CinematicPathRig) - [NEW]
    │   └── Camera
    └── CameraZone (CameraZone) - [NEW]
        └── CollisionShape (Defining the "sweet spot" area)


B. New Exported Variables (HoloTerminalV2.gd)

Add these variables to control the new behavior via the Inspector:

    use_cinematic_view (bool): Master switch to enable/disable this feature. Default: true.

    hide_hologram_in_view (bool): If true, the ScreenMesh (the 3D volume) will hide when the cinematic camera is active, leaving only the 2D UI visible (if rendered separately) or simply clearing the view. Interpretation: This prevents the 'glitchy' hologram shader from obscuring the UI when looking closely.

    close_on_exit_zone (bool): If true, leaving the CameraZone automatically toggles the terminal off (is_active = false). Default: true.

3. Logic Implementation Details

The HoloTerminalV2.gd script needs to manage the CameraZone based on its own state (is_active).
A. State Synchronization (_update_visuals / step)

The CameraZone should only trigger the camera if the terminal is fully open.

    On _ready():

        Get reference to $CinematicSetup/CameraZone.

        Disable the zone initially: CameraZone.monitoring = false.

        Connect signals from CameraZone:

            cinematic_entered -> _on_camera_zone_entered

            cinematic_exited -> _on_camera_zone_exited

    On is_active Change (Open/Close):

        When is_active becomes true (Terminal Opening):

            Enable CameraZone.monitoring = true.

            Crucial check: Since the player is likely already standing there, enabling monitoring might not trigger body_entered immediately in some physics ticks. We must manually check CameraZone.get_overlapping_bodies() or force an update. If player is found, manually call CameraZone._on_body_entered(player).

        When is_active becomes false (Terminal Closing):

            Disable CameraZone.monitoring = false.

            This should naturally release the camera via the zone's logic, but we can force CameraZone._deactivate_cinematic() to be safe.

B. Signal Handlers

    _on_camera_zone_entered(mode):

        If hide_hologram_in_view is true: Set $ScreenContainer/ScreenMesh.visible = false.

        (Optional) Change TerminalUI state to "Focused Mode".

    _on_camera_zone_exited():

        Restore visibility: $ScreenContainer/ScreenMesh.visible = true.

        If close_on_exit_zone is true: Call set_active(false) to close the terminal animations.

4. Signal Wiring (Editor Friendly Strategy)

To make this easy to edit without hardcoding paths in script:

    The CameraZone (child node) should store the target_rig_id.

    The TerminalCamRig (sibling node) should have that ID.

    Best Approach: Instead of IDs, since they are in the same scene, the script can assign them dynamically.

        In _ready(), HoloTerminalV2 finds the child CinematicRig.

        It assigns that rig's path to the child CameraZone.cinematic_rig_path.

        This ensures that duplicating the Terminal doesn't break camera links (unique IDs are not needed for local setups).

5. Integration with OYS/Replay

    Determinism: The CameraZone logic relies on body_entered (physics). This is compatible with SessionManager.

    Snapshots: The is_active state is already snapshotted. The camera state is derived from is_active + player position, so no new snapshot data is strictly needed for the terminal itself (the Player snapshot stores position, which dictates if they are in the zone).

Appendix A: Cinematic Input Handling (Mouse Integration)

When the cinematic camera is active, the mouse should switch from camera control to UI interaction.

Cursor Visibility: A mouse cursor texture (e.g., a simple crosshair or pointer) must appear on the terminal screen UI.

Input Mapping: Mouse movement should control the cursor position within the Holo Terminal UI.

Click Interaction: Left mouse clicks should be passed to the terminal UI as standard click events.

Context Switching: This input mode is active only when the player is inside the active HoloTerminal zone and the terminal is is_active. Exiting the zone or closing the terminal should revert mouse control to standard camera perspective.