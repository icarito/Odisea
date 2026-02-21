# Audio Manager

**Source:** `core_v2/autoloads/AudioManager.gd`

The `AudioManager` is a global autoload responsible for managing Background Music (BGM) and Sound Effects (SFX) in a centralized, priority-based manner. It supports integration with the `Godot-Mixing-Desk` plugin but provides robust fallbacks if the plugin is missing.

## Key Features

-   **Priority-Based BGM Zones:** Multiple BGM zones can be active simultaneously. The system prioritizes zones based on volume (smaller volume = higher priority, assuming smaller zones are more specific).
-   **Cross-Fading:** Smoothly transitions between tracks using an internal `Tween` and two `AudioStreamPlayer` nodes (`BGMPlayer1`, `BGMPlayer2`).
-   **Mixing Desk Integration:** Automatically detects and uses `MixingDeskMusic` and `MixingDeskSound` nodes if present in the scene tree.
-   **Fallback System:** If Mixing Desk is not found, it seamlessly falls back to standard `AudioStreamPlayer` playback.

## Usage

### Registering a Zone
BGM Zones (e.g., `BGMZone.gd`) register themselves with the manager upon player entry:

```gdscript
AudioManager.register_zone(self)
```

And unregister upon exit:

```gdscript
AudioManager.unregister_zone(self)
```

### Playing SFX
Sound effects can be triggered globally:

```gdscript
AudioManager.play_sound("DoorOpen", position)
```

If `MixingDeskSound` is available, it plays the named sound. Otherwise, it prints a warning (unless a specific fallback is implemented in the caller).

## Internal Logic

1.  **_update_bgm()**: Called whenever zones change. Sorts active zones by priority.
2.  **_crossfade_to()**: Manages the volume interpolation between the current and target stream.
3.  **reset()**: Stops all audio and clears active zones (useful for scene transitions or replays).
