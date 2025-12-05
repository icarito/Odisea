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


## 2025-12-03
- Arreglar PlayerController: giro automático al correr/caminar y animación de flotar.
- Vientos/Fuerzas ascendentes: script y escena implementados.
- Muerte por caída: KillZone implementado.
- Respawn a estado viable: PlayerManager extendido con checkpoints.
- Ajustar MovingPlatform.gd para estabilidad.
- Añadir KillZone y WindZone en criogenia.tscn.

## 2025-12-05
### Avances de commits recientes (completado)
- Integración de multiplayer split-screen (feat: Implement split-screen multiplayer).
- Mejoras en controles analógicos/joystick: soporte para configuración de joystick, depuración de entrada, ajustes en rotación de cámara/jugador (e.g., giro automático, flotación, nado).
- Optimizaciones de FPS: remover efectos pesados, ajustar luces para GLES2, refactor de código para legibilidad.
- Exportaciones: presets para HTML5/PWA, web export y deployment via GitHub Actions, soporte ARM64/Linux/Android.
- Menú y UI: splash screen, efectos de desvanecimiento, botón salir, imagen inicio.
- Housekeeping: eliminar material obsoleto, ajustar configuraciones de proyecto (e.g., filtros de exportación, opciones de calidad).

### Tareas movidas de TODO (completado)
- Conveyor en plataforma principal: calibrado y ajustado en criogenia.tscn (empuje aplicado a RigidBody, shader sutil).
- WindZone y KillZone: integrados en criogenia.tscn con ajustes (partículas, efecto visual de muerte).
- Plataformas móviles: ajustadas para estabilidad en MovingPlatform.gd.
- SceneManager y Loading Screens: autoload SceneManager agregado para pantallas de carga.
- Integración de audio y LevelBGM: adjuntado a nivel, BGM cambia en muerte/respawn.
