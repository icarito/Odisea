# Scene Transition System Specification

## Overview
The Odisea Scene Transition System is designed to manage seamless movement between different game environments in Godot 3.x. It aims to eliminate screen freezing during level loads by utilizing asynchronous background loading (`ResourceInteractiveLoader`) and provides tools for rich visual and auditory transitions (e.g., fades, wipes, loading screens).

## Core Requirements
1.  **Asynchronous Loading:** The main thread must not block while loading heavy `.tscn` files. A progress bar or loading animation should be displayable.
2.  **Visual Polish:** Support for customizable visual transitions (fade to black, crossfade, shader-based wipes, loading screens with tips).
3.  **Audio Handling:** Ability to fade out current Background Music/Ambience and fade in the new environment's audio to prevent abrupt cuts.
4.  **State Passing & Spawn Points:** Ability to preserve player state (health, inventory) and define specific "Spawn Points" or "Doors" so the player appears at the correct location in the new scene.
5.  **OdysseyScript (OYS) Integration:** Allow triggering scene changes directly from OYS commands.

## Architecture Architecture

### 1. `SceneManager` (Autoload / Singleton)
The core controller responsible for coordinating the transition.

*   **Variables:**
    *   `loading_thread`: For asynchronous loading (or use `ResourceInteractiveLoader` in `_process`).
    *   `current_scene`: Reference to the currently active scene.
    *   `next_scene_path`: Target `.tscn` path.
    *   `transition_params`: Dictionary containing spawn location IDs, state data, and chosen visual transition type.
*   **Methods:**
    *   `goto_scene(path: String, params: Dictionary = {})`: Initiates the transition process.
    *   `_process(delta)`: Polls the `ResourceInteractiveLoader` to get loading progress.
    *   `_set_new_scene(resource: PackedScene)`: Swaps out the old scene tree, instances the new one, and injects parameters.

### 2. `TransitionLayer` (CanvasLayer Autoload)
A persistent UI layer sitting above all game content, containing a `ColorRect` for shaders and an `AnimationPlayer`.

*   **Animations:**
    *   `fade_out`: Animates alpha 0 to 1.
    *   `fade_in`: Animates alpha 1 to 0.
    *   `loading_screen_show`: Brings up a dedicated loading UI with a progress bar.
*   **Signals:**
    *   `transition_covered_screen`: Emitted when the screen is fully obscured (safe to swap scenes behind the curtain).
    *   `transition_finished`: Emitted when the scene is fully revealed.

### 3. Spawn Points & Session Manager Integration
When a scene is loaded, the `SceneManager` passes a `target_spawn_id` to the `SessionManager`. 
*   **`SpawnPointV2` Node:** Placed in levels. Has a unique `spawn_id` exported variable.
*   **Player Relocation:** After the scene is instanced, `SessionManager` looks for a `SpawnPointV2` matching `target_spawn_id` and teleports the `Pilot` there before the screen fades in.

### 4. OYS Integration
A new command injected into `OYS_Interpreter_v2`:
```oys
CHANGE_SCENE res://core_v2/levels/TestScene_v2.tscn "fade" "spawn_door_A"
```

## Transition Flow Lifecycle
1.  **Trigger:** Player walks into a `TransferZone` or an OYS script calls `CHANGE_SCENE`.
2.  **Curtain Call:** `SceneManager` calls `TransitionLayer.play("fade_out")`. Input is disabled.
3.  **Background Load:** Once the screen is black, `SceneManager` begins loading the new `.tscn` via `ResourceInteractiveLoader`.
4.  **Scene Swap:** When loading hits 100%, the old scene is `queue_free()`'d, and the new scene is added to the tree.
5.  **Initialization:** The new scene's `_ready()` functions run. `SessionManager` teleports the player to the requested `SpawnPointV2`.
6.  **Reveal:** `TransitionLayer` plays `"fade_in"`. Input is restored.

## Handling Edge Cases
*   **Physics Jitter:** Moving the player immediately on `_ready` can sometimes result in camera/physics jitter. The system should yield for one `physics_frame` after teleportation before fading back in.
*   **OYS State Preservation:** If an OYS script spans across a level transition, execution must pause, wait for `transition_finished`, and then resume in the new scene's context without losing local variables.
