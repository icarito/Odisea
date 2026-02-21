# OdiseaOS Subsystems

This directory documents the core subsystems of the Odisea project (`core_v2`).

## Index

### Core Systems

-   **Session Manager**: [Session Manager Documentation](session_manager.md)
    -   Orchestrates the game loop, input recording, replays, and OYS execution.
    -   Manages deterministic simulation and state validation.

-   **Performance Monitor**: [Performance Monitor Documentation](performance_monitor.md)
    -   Tracks CPU budget, FPS, lag spikes, and supports detailed profiling.
    -   Provides tools for regression testing performance.

### Gameplay Systems

-   **Odyssey Script (OYS)**: [OYS Feature Documentation](../canon/feature_odisea_script.md)
    -   Domain-Specific Language (DSL) for deterministic scripting of tests and cutscenes.
    -   Used extensively for integration tests and regression testing.

-   **Audio Manager**: [Audio Manager Documentation](audio_manager.md)
    -   Manages priority-based BGM zones and cross-fading.
    -   Handles SFX playback with optional Mixing Desk integration.

-   **Logic Circuit System (OLCS)**: [Circuit System Documentation](../../core_v2/systems/circuit/README.md)
    -   Node-based visual scripting for logic gates and connections between props.
    -   Supports complex behaviors like doors, switches, and delays.

-   **Dynamic Footstep System**: [Footsteps Documentation](../../core_v2/systems/footsteps/README.md)
    -   Detects surface materials and plays appropriate footstep sounds.
    -   Configurable via `FootstepProfile` resources.

### Physics & Interaction

-   **Pushable Box**: [Pushable Box Feature](../canon/feature_pushable_box.md)
    -   Hybrid Kinematic/RigidBody physics object for deterministic interaction.

-   **Movement & Gamefeel**: [Movement Gamefeel](../canon/feature_refine_movement_gamefeel.md)
    -   Documentation on player movement tuning and responsiveness.
