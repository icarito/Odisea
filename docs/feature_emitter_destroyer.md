Technical Specification: PropEmitterArea and PropDestroyerArea (core)

1. Architectural Vision and Strategic Objective

The transition of the core framework from static prop placement to a dynamic, area-based management system is a critical requirement for level design scalability. In the context of large-scale environments like the 8km colony ship in Odisea, manual prop management is unsustainable. The PropEmitterArea and PropDestroyerArea provide an automated lifecycle for entities within defined volumes, ensuring that the simulation remains high-performance while adhering to our project’s strict mandate for deterministic physics.

The "So What?" factor centers on the decoupling of prop lifecycle management from the entities themselves (such as PushableBox). By abstracting spawning and cleanup into external controller areas, we eliminate the technical debt associated with hard-coded object references. This shift simplifies the physics state-tracking logic within the SessionManager, as the system no longer needs to track "sleeping" static objects that may never be interacted with. Instead, the PersistenceManager only monitors active, registered entities, significantly reducing the complexity of replay data and ensuring high-fidelity accuracy across different hardware sessions. All components within this specification strictly adhere to the core/components directory structure and Godot 3.6.x naming conventions established in the recent refactor.

2. Core Design Principles: Determinism and Performance

To prevent "drift" during simulation replays—as defined by our "Ground Truth" requirements in core/tests/test_determinism.gd—every component must ensure transform updates and state changes are reproducible. The following constraints are non-negotiable for any architectural implementation within core.

Determinism vs. Performance Constraints	Requirement Description
Fixed-Step Logic	All transform updates, spawn calculations, and destruction checks must occur within _physics_process. Dependency on frame-rate-dependent _process is strictly prohibited.
State Persistence	Every spawned entity must be registered with PersistenceManager.gd immediately upon instantiation to ensure it is captured in save states, checkpoints, and replay logs.
Resource Management	High-frequency calls to instance() or Object.new() during simulation steps are forbidden. PropEmitterArea must implement a pre-instanced object pool at _ready to prevent frame-spikes.
State-Bleeding Prevention	Emitters must implement a reset() function that clears all spawned props to ensure one replay session does not contaminate the starting state of the next.

The following sections detail the specific functional implementation of these areas to ensure they satisfy these architectural constraints.

3. Functional Specification: PropEmitterArea

The PropEmitterArea serves as the mandatory, controlled entry point for introducing new entities into the active simulation. It provides a standardized interface for generating props while maintaining the integrity of the deterministic world state.

* Spawn Logic: The emitter utilizes a PackedScene property to define the entity type (initially targeting PushableBox.tscn).
* Area Definition: Emission volumes must be defined using CollisionShape nodes (Box or Sphere) to allow for designer-facing visualization within the Godot editor.
* Deterministic Seeding: The emitter must use an exported seed variable for random spawn offsets. This seed should default to a global value provided by SessionManager.gd to ensure the emitter remains in sync with the global simulation seed.
* Rate Control: Designers must define spawn_limit (max concurrent entities) and emission_rate (entities per second).
* Registration Signal: This signal is the single point of failure for replay consistency. It is mandatory for "frame-zero" state synchronization. Upon spawning a KinematicBody or RigidBody, this signal must inform the SessionManager and TeleportSystem of the new entity's existence, allowing its initial transform and ID to be logged before the first physics step occurs.

To maintain deterministic integrity, the emitter must respond to global reset events by flushing its object pool and clearing all active references, preventing state-bleeding between test runs.

4. Functional Specification: PropDestroyerArea

Automated cleanup is vital for maintaining frame rates and preventing "state bloat" in long-running simulations. The PropDestroyerArea is responsible for the immediate removal of entities that have exited the playable simulation space.

* Target Filtering: The area must be configured with its collision_mask set to Layer 2 (designated for "things" in core). It must further validate targets using class checks (e.g., is PushableBox or is InteractableBase) to ensure internal player actors are not accidentally cleared.
* Deterministic Iteration: If multiple bodies are detected within the area in a single physics frame, the order of destruction must be consistent to prevent drift. The destroyer must sort detected bodies by their internal get_instance_id() before initiating the cleanup loop.
* Cleanup Protocol: To prevent null-reference errors during replay scrubbing, the destroyer must unregister the entity from the PersistenceManager and any active TeleportSystem tracking slots before calling queue_free().
* Visuals vs. Physics: Physics removal must be immediate. If an "Animated Deletion" is required (e.g., a fade-out), this must be handled by a separate View/Visual component (e.g., PropVisualFXV2). The PropDestroyerArea logic only concerns itself with the immediate removal of the CollisionObject from the physics server.
* TeleportSystem Integration: The destroyer must hook into the TeleportSystem respawn logic. If the player resets to a checkpoint or death-respawns, the area may be required to "flush" its tracked entities to reset the level state.

5. Integration and Generalization Strategy

Consistent with the "Generalizable Components" philosophy of core/components, these areas are designed to be agnostic of the specific prop type, provided the prop inherits from InteractableBase.

Initial Implementation: PushableBox The system will be validated in core/levels/TestScene_PushableBox.tscn. By utilizing the base class for registration, the emitter can handle any future core prop without script modifications.

Current Static Implementation	Proposed Dynamic Implementation
Manual Placement: Every box requires manual placement in core/levels/.	Automated Generation: Volumes handle density, reducing manual editor labor.
Fixed Memory: Every object in the scene tree consumes memory and tracking overhead.	Optimized State: PersistenceManager only tracks active, spawned entities.
State Bleeding: Residual transforms from previous runs can contaminate current runs.	Guaranteed Clean State: Mandatory reset() and flush() logic ensures a fresh simulation.
Indeterministic Cleanup: Manual deletion or simple queue_free can cause replay drift.	Deterministic Iteration: ID-based sorting ensures identical destruction order.

These components are essential to solidifying the core ecosystem, providing the infrastructure necessary for a robust, high-performance, and fully deterministic immersive simulation.
