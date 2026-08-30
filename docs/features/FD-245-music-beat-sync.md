# FD-245: Music-Beat Event Synchronization System

**Status:** spec  
**Author:** Odiseo  
**Date:** 2026-07-01  
**Branch:** `feature/FD-245-music-beat-sync`  
**Target:** Godot 3.x, GDScript 1.x

---

## Overview

Sistema que permite sincronizar eventos de entorno (explosiones, fugas de plasma, sparks, luces) con el beat y compás de la música de fondo. AudioManager emite señales de beat/compás/downbeat, y un nuevo componente `BeatSyncTrigger` las escucha para activar/desactivar emitters u otros nodos en momentos musicales precisos.

**Uso inmediato:** Core.tscn (prólogo) — explosiones y fugas de plasma sincronizadas con "Elias Wake.mp3".

## Motivation

- El prólogo actual es pasivo: el jugador solo espera. Agregar eventos sincronizados con la música transforma la experiencia en algo cinematográfico.
- Reusable: cualquier nivel puede tener eventos musicales sin lógica ad-hoc.
- Bajo acoplamiento: AudioManager emite señales globales, los triggers escuchan sin conocerse entre sí.

## Scope

### In Scope
1. AudioManager: señales `beat`, `measure`, `downbeat` + propiedad `bpm` + tracking de posición
2. `BeatSyncTrigger`: componente configurable que escucha señales y ejecuta acciones
3. Core.tscn: integrar triggers para LeakEmitter/SparkEmitter/FireEmitter existentes

### Out of Scope
- Análisis automático de BPM desde archivos de audio (BPM se configura manualmente)
- Sincronización con MixingDesk (MDM/MDS)
- Efectos visuales rítmicos genéricos (eso puede ser FD aparte)
- Timeline/sequencer complejo con curva de beats

## Architecture

```
AudioManager (autoload)
  ├── bpm: float = 120.0
  ├── time_signature: int = 4
  ├── beat_offset: float = 0.0  (seconds to skip before beat 0)
  │
  ├── signal beat(beat_number: int)          # cada beat
  ├── signal measure(measure_number: int)     # primer beat de cada compás
  ├── signal downbeat(measure_number: int)    # beat 1 de cada compás (= measure)
  │
  └── _physics_process():
       ├── poll active player playback position
       ├── detect beat crossings
       └── emit signals

BeatSyncTrigger (Spatial/Node)
  ├── target_path: NodePath
  ├── trigger_mode: "activate" | "deactivate" | "toggle" | "call"
  ├── method: String = "activate"
  ├── beat_pattern: Array[int]       # ej: [1, 5, 9] para beats específicos
  ├── measure_pattern: Array[int]    # ej: [1, 3, 5]
  ├── every_n_beats: int = 0         # 0 = disabled, 4 = cada 4 beats
  ├── every_n_measures: int = 0
  ├── repeat: bool = true
  ├── max_triggers: int = -1         # -1 = infinito
  │
  └── connect to AudioManager signals → call target method
```

## Files

### Modify
| File | Change |
|------|--------|
| `core_v2/autoloads/AudioManager.gd` | Add BPM tracking, beat/measure/downbeat signals, `_track_beat()` in physics process |

### Create
| File | Purpose |
|------|---------|
| `core_v2/components/BeatSyncTrigger.gd` | Listens to AudioManager beat signals, triggers target node |
| `core_v2/components/BeatSyncTrigger.tscn` | Empty scene with script attached |

### Integration (Core.tscn)
| File | Change |
|------|---------|
| `scenes/levels/act0/Core.tscn` | Add BeatSyncTrigger instances |
| `scenes/levels/act0/PrologueDirector.gd` | Set `AudioManager.bpm` when music starts (or expose bpm in Core.tscn) |

## Detailed Spec

### 1. AudioManager — Beat Tracking

**New exported properties:**
```gdscript
export(float, 1.0, 300.0, 1.0) var bpm: float = 120.0
export(int, 1, 16) var time_signature: int = 4
export(float, 0.0, 60.0, 0.01) var beat_offset: float = 0.0
```

**New signals:**
```gdscript
signal beat(beat_number: int)
signal measure(measure_number: int)
signal downbeat(measure_number: int)
```

**Tracking logic (in `_physics_process`):**
- If no active player or music is paused, skip.
- Get `playback_position` from `_active_player`.
- Apply `beat_offset`: `effective_pos = max(0.0, position - beat_offset)`.
- Calculate: `current_beat_float = effective_pos * (bpm / 60.0)`.
- `current_beat_int = int(floor(current_beat_float))`.
- Compare against stored `_last_beat_int`. For each new integer beat crossed: emit `beat(n)`.
- If the new beat is the first of a measure (`beat_int % time_signature == 0`): emit `measure(m)` and `downbeat(m)`.
- Handle loop detection: if `current_beat_float < _last_beat_float_raw - 0.5`, reset beat counter.

**Edge cases:**
- Crossfade: when switching `_active_player`, initialize beat counters to match the new player's position (store per-player beat state like zone positions).
- BPM changes: if `bpm` is set during playback, on next `_track_beat` the calculation naturally adapts. No history needed.
- Headless: beat tracking still runs (no audio needed for signal emission).
- Startup gate: emit signals immediately; triggers can check startup state themselves.

### 2. BeatSyncTrigger

**Properties:**
```gdscript
export(NodePath) var target_path: NodePath
export(String, "activate", "deactivate", "toggle", "call") var trigger_mode: String = "activate"
export(String) var method_name: String = "activate"
export(Array, int) var beat_pattern: Array = []
export(Array, int) var measure_pattern: Array = []
export(int, 0, 64) var every_n_beats: int = 0
export(int, 0, 64) var every_n_measures: int = 0
export(bool) var repeat: bool = true
export(int, -1, 999) var max_triggers: int = -1
export(bool) var wait_for_runtime_startup: bool = true
```

**Behavior:**
- `_ready()`: resolve target, connect to AudioManager signals based on configured patterns.
  - If `beat_pattern` not empty → connect to `AudioManager.beat`.
  - If `measure_pattern` not empty → connect to `AudioManager.measure`.
  - If `every_n_beats > 0` → connect to `beat` and filter by modulo.
  - If `every_n_measures > 0` → connect to `measure` and filter by modulo.
- On signal received: call `_trigger()`.
- `_trigger()`: call `target.method_name()` or `target.trigger_mode()` depending on mode.
- `_call_target()`: safe call with `has_method()` check. If target doesn't respond, print warning once.
- Counter tracking: `_trigger_count` incremented per trigger. If `max_triggers > 0` and `_trigger_count >= max_triggers`, disconnect signals and stop.

**Startup gate:**
- If `wait_for_runtime_startup` is true, defer signal connection until SessionManager reports gate open (same pattern as LeakEmitter).

### 3. Core.tscn Integration

**Setup (manual, in editor):**
- `PrologueDirector` sets `AudioManager.bpm = <BPM of Elias Wake>` when music starts.
  - Elias Wake BPM needs to be determined manually (Sebastian provides this).
  - Default fallback: expose `export(float) var music_bpm` on PrologueDirector.
- Place `BeatSyncTrigger` nodes in Core.tscn, each targeting a LeakEmitter, FireEmitter, or SparkEmitterV2.

**Example triggers (to be tuned with actual BPM):**
| Trigger | Target | Pattern | Effect |
|---------|--------|---------|--------|
| BeatSyncTrigger_1 | PlasmaLeak_A | `every_n_beats: 8` | Plasma fugue pulses every 8 beats |
| BeatSyncTrigger_2 | SparkEmitter_1 | `measure_pattern: [2, 4, 6]` | Sparks on measures 2, 4, 6 |
| BeatSyncTrigger_3 | ExplosionFlash | `beat_pattern: [1]` | Single explosion on beat 1 (downbeat) |

**⚠️ The actual beat/measure placements MUST be tuned by Sebastian in-editor after testing with the real music track.**

**LeakEmitter behavior on beat sync:**
- `LeakEmitter` in burst mode: calling `activate()` triggers one burst cycle (duration + fadeout).
- Calling `deactivate()` during a burst cuts it off.
- For beat-synced pulses: use burst mode with `interval: 0` (constant mode off), trigger `activate()` on beat.
- Since `activate()` restarts the burst from duration, repeated beat-synced calls will keep it pulsing in time.

## Acceptance Criteria

1. `AudioManager` emits `beat(n)` every beat when BGM is playing, with correct `bpm`.
2. `AudioManager` emits `measure(m)` on beat 1 of each measure.
3. `BeatSyncTrigger` correctly calls target method on matching beat/measure patterns.
4. `every_n_beats` and `every_n_measures` filters work with modulo logic.
5. `max_triggers` limits trigger count correctly.
6. Loop detection resets beat counter when music loops.
7. Crossfade doesn't cause beat glitches (double-emits or skipped beats).
8. Core.tscn has at least 3 BeatSyncTrigger instances creating visual events synced to music.
9. No performance regression: beat tracking in physics_process adds negligible overhead.
10. Works in HTML5 export (no threading assumptions).

## Dependencies

- None. Uses existing AudioManager, LeakEmitter, FireEmitter, SparkEmitterV2.
- Does NOT require MixingDesk plugin.

## Risks

- **BPM drift**: if AudioStreamPlayer has slight playback speed variation, beats may drift over long tracks. Mitigation: for tracks under 3 min with constant BPM, drift is imperceptible.
- **Crossfade complexity**: during crossfade both players are active. We track only `_active_player`. The transition window (fade_time, typically 1-2s) may cause brief beat alignment shift. Acceptable for game feel.
- **Manual BPM**: requires Sebastian to know/measure BPM of each track. No auto-detection.
