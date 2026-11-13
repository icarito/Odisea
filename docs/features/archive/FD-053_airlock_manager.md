# FD-053: AirlockManager — Autoload for Seamless Airlock Transitions

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-06
**Updated:** 2026-06-06

## Problem

The current airlock system (AirlockZoneV2 + TransitionPortal + SceneManager) reloads scenes on each transition — the player fades out, the target scene loads, the player fades in. This works for single transitions but breaks for:

1. **Seamless transitions between domes** — Dome_Crio needs to transition to OdiseaExterior (the spiral exterior) and back. Reloading the exterior scene destroys the streaming state (plates, facades, LOD).
2. **Player state preservation** — the player's velocity, momentum, and Cargol companion get lost on scene reload.
3. **Seamless feel** — the current fade-out + load + fade-in takes ~1-2 seconds and breaks the sense of a connected ship.
4. **Multiple domes** — future domes (Dome_Taller, Dome_Hab) need the same transition pattern. A single manager avoids duplication.

We need an `AirlockManager` autoload that maintains a singleton `AirlockChamber` **outside the scene tree**, reparents it on each transition, and recalculates its transform in the new coordinate space — making transitions feel instantaneous.

## Solution

Create `AirlockManager` as a Node autoload (singleton) that:

1. **Holds a pool of `AirlockChamber` instances** (from the existing `AirlockChamber.tscn`) outside the scene tree.
2. **On transition request**: reparents the chamber into the source scene, plays the door-close animation, captures the player's relative position, unparents the chamber (keeping it alive), loads/activates the target scene, reparents the chamber into the target scene, recalculates the player's transform relative to the target airlock, plays door-open.
3. **Supports two transition modes**:
   - **Dome-to-exterior** (Dome_Crio → OdiseaExterior) — loads the exterior scene, places player at correct spiral/plate, preserves streaming state.
   - **Exterior-to-dome** (OdiseaExterior → Dome_Crio) — returns to dome, preserves player progress.

### Key Design Decisions

- **Chamber is persistent.** It never gets freed. Just reparented. The door-open/close sounds and animations play once per transition regardless of scene.
- **Player is reparented, not re-instantiated.** The same Pilot node moves between scene trees. This preserves velocity, crouch state, companion references.
- **OdiseaExterior is paused, not destroyed.** On exterior-to-dome transitions, the exterior pauses plate streaming and LOD updates. On return, streaming resumes from the player's last position.

### Considered Options

- **Option A: SceneManager reload (current)** — Works but destroys exterior streaming state. No good for domes.
- **Option B: Separate airlock scene overlay** — Load airlock chamber as its own scene on top of everything. Breaks physics and camera layers.
- **Option C: Persistent chamber singleton (selected)** — Simple, no scene overhead, preserves all state. Chamber always exists, just moves.

## Architecture

```
AirlockManager (autoload)
├── _chamber_pool: Array[AirlockChamber]  (1-3 pre-instanciados)
├── _active_chamber: AirlockChamber        (el que está en uso)
├── _transition_queue: Array[TransitionRequest]
├── _player_velocity_cache: Vector3        (velocidad durante la transicion)
│
├── request_transition(source_id, target_scene, target_spawn, mode)
├── _execute_dome_transition(request)
├── _execute_exterior_transition(request)
├── _reparent_chamber(target_parent, target_transform)
├── _reparent_player(player, target_parent, local_transform)
├── _pause_exterior()
├── _resume_exterior()
└── _recalculate_relative_transform(player_pos, source_airlock, target_airlock)
```

### Dome-to-Exterior Transition Flow

```
1. Player enters AirlockZoneV2 in Dome_Crio.tscn
2. AirlockZoneV2 calls AirlockManager.request_transition(
       "crio_airlock",
       "res://core_v2/levels/OdiseaExterior.tscn",
       "exterior_spawn_01"
   )
3.   → Disables player input
4.   → Reparents chamber to Dome_Crio scene root at source airlock position
5.   → Plays door-close animation (0.3s)
6.   → Captures player's relative position to chamber center
7.   → Captures player velocity
8.   → Unparents chamber from Dome_Crio (stays alive in AirlockManager)
9.   → Reparents player to AirlockManager (player stays alive, detached)
10.  → Calls SceneManager.load_scene(target_scene) via TransitionLayer
11.  → On target scene ready (OdiseaExterior):
       a. Reparents chamber to exterior scene root at target spawn transform
       b. Reparents player to exterior scene, recalculates position from chamber
       c. Restores player velocity
12.  → Plays door-open animation (0.3s)
13.  → Re-enables player input
14.  → Emits signal: transition_completed("crio_airlock", "odisea_exterior", "exterior_spawn_01")
```

### Exterior-to-Dome Transition Flow

```
1. Player enters AirlockZoneV2 in OdiseaExterior (placed at a plate/spiral)
2. AirlockManager.request_transition(
       "exterior_airlock_01",
       "res://core_v2/levels/interiors/Dome_Crio.tscn",
       "crio_return_spawn"
   )
3.   → Pauses OdiseaExterior processing (plate streaming, LOD updates)
4.   → Same chamber/player reparent flow as above
5.   → On Dome_Crio ready: places player at return spawn
6.   → Resumes OdiseaExterior (keeping it in memory for fast return)
```

## Files to Modify / Create

| File | Action |
|------|--------|
| `core_v2/autoloads/AirlockManager.gd` | **New** — the singleton |
| `core_v2/components/AirlockZoneV2.gd` | Modify — replace direct SceneManager calls with AirlockManager.request_transition() |
| `core_v2/levels/OdiseaExterior.gd` | Modify — add `pause_streaming()` and `resume_streaming()` methods called by AirlockManager |
| `core_v2/data/DomeRegistry.gd` | Modify — expose spawn-to-plate mapping for exterior transitions |
| `core_v2/levels/interiors/Dome_Crio.tscn` | Modify — add AirlockZoneV2 nodes at airlock positions with proper spawn ids |
| `core_v2/autoloads/SceneManager.gd` | Modify — expose `load_scene_preserve()` for AirlockManager to trigger loads without destroying current scene immediately |
| `core_v2/props/AirlockChamber.tscn` | Review — ensure chamber is poolable (resettable state, deterministic door animation) |
| `core_v2/player/PlayerControllerV2.gd` | Modify — add `reparent_to(new_parent, local_transform)` method |
| `project.godot` | Modify — register AirlockManager autoload |

## Integration Points

### With OdiseaExterior + DomeRegistry

- When transitioning **from dome to exterior**, AirlockManager needs to know which spiral/plate to place the player on. The `target_spawn` string should resolve to a `(spiral, plate)` pair via a registry in DomeRegistry.
- The chamber transform in the exterior must account for the **cylindrical coordinate system** — relative angle + radius, not just XYZ offset from scene origin.
- When **pausing** OdiseaExterior, the manager should set a `_paused` flag that stops `_process` in OdiseaExterior and ScaffoldStreamController. The scene stays in memory.

### With Dome_Crio.tscn

- The dome scene needs one or more `AirlockZoneV2` child nodes placed at the airlock doorways.
- Each AirlockZoneV2 exports:
  - `target_scene: String` → OdiseaExterior.tscn
  - `target_spawn_id: String` → a named spawn point in the exterior
  - `transition_mode: String` → "dome_to_exterior"

### With PlayerControllerV2

- Player needs `reparent_to(new_parent: Spatial, local_transform: Transform)`. On reparent, the controller must re-resolve its camera paths and physics state.
- The `physics_grounded` flag will re-settle after 1-2 frames — acceptable.

## State That Must Survive Reparenting

- Player transform (world position preserved via relative calc to chamber center)
- Player velocity (cached in AirlockManager during transition)
- Cargol companion reference (if active)
- Current interaction target
- Animation state (can reset to standing on exit — acceptable)

## Edge Cases

- **Player exits during transition:** AirlockZoneV2 disables input during the sequence. Already handled.
- **Multiple simultaneous requests:** Queue them, process one per frame max.
- **Chamber pool exhausted:** Pre-instantiate 2 chambers max; rarely more than 1 in use.
- **Target scene fails to load:** Fall back to SceneManager error handling, fade in with error message.
- **Return to exterior after dome visit:** Exterior should resume streaming where it left off (same spiral/plate).

## Verification

1. Place AirlockZoneV2 in Dome_Crio.tscn pointing to OdiseaExterior. Transition should show door-close, brief load (< 1s), door-open in exterior at correct spiral/plate.
2. Return through same airlock. Should land in the same spot in Dome_Crio.
3. Player velocity should be preserved across transition (test with running jump through airlock).
4. Cargol companion (if attached) should follow through transition.
5. OdiseaExterior streaming should resume correctly on return (domes and plates visible, no pop-in).
6. Stress test: 5 rapid transition requests. Queue should drain without crashes.

## Open Questions

- Should the chamber visual be visible during the load? (Yes — player sees the chamber interior, not a black screen. The chamber walls hide the missing geometry.)
- Does OdiseaExterior stay in memory when going into a dome? (Yes — it remains paused. The exterior scene is too heavy to unload/reload every dome visit.)
- How does AirlockManager know which spiral/plate corresponds to a spawn_id? (DomeRegistry should expose a `get_spawn_transform(spawn_id: String) -> Transform` mapping.)
