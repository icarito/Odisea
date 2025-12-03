# DONE — Odisea MVP Acto I

Registro de tareas completadas y cambios integrados.

## 2025-12-02

### Plan del día (completado)
- BGM mínimo: usar `autoload/AudioManager.gd` en `Menu.tscn` y `criogenia.tscn` (tema menú: `assets/music/Orbital Descent.mp3`; nivel: `assets/music/Rust and Ruin.mp3`). Estado: listo (ambas escenas reproducen BGM via `LevelBGM.gd`).
- Kill/Respawn + Checkpoints: `KillZone.gd` + `KillZone.tscn` bajo el nivel; extender `PlayerManager.gd` con `last_checkpoint_transform` y `respawn()`; `Checkpoint.tscn` que notifique al manager. Estado: funcional (muerte/respawn, último checkpoint, música cambia en muerte y reinicia al respawn).

### Implementación técnica (completado)
- `scripts/Conveyor.gd` — aplica velocidad constante a `KinematicBody`/`RigidBody` dentro (vector tangente de banda). Exponer: `push_velocity`.
- `scenes/common/Conveyor.tscn` — `Area` + `CollisionShape` + Mesh plano con textura de flechas.
- `scripts/WindZone.gd` — fuerza vertical; Exponer: `lift_force`, `max_speed`.
- `scenes/common/WindZone.tscn` — `Area` + `CollisionShape` + partículas direccionales.
- `scripts/KillZone.gd` — al entrar, emite señal de muerte al `PlayerManager`.
- `scenes/common/KillZone.tscn` — `Area` grande bajo plataformas.
- `scenes/common/Checkpoint.tscn` — `Area` + marcador visual; notifica a `PlayerManager`.

### Integración de audio (completado)
- Autoload `AudioManager.gd` registrado en `project.godot`.
- Reproducir BGM en `Menu.tscn` (`Orbital Descent.mp3`).
- Reproducir BGM en `criogenia.tscn` (`Rust and Ruin.mp3`).

### Cambios recientes
- Ajustar transparencia del material en `WindZone` y añadir partículas.
- Corregir interacción del conveyor con Elias.
- Implementar efecto visual de "cerrar los ojos" en `KillZone`.
- Cambiar música al morir y reiniciarla al hacer respawn.
- Respawn accepts any key or button press.
- Added "Offline" label to death screen.
- WindZone: partículas billboard emisivas, distribución en volumen y sin gravedad.
- Conveyor: shader más sutil (menos contraste/emisión) y empuje aplicado también a `RigidBody`.
