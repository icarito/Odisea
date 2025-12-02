# TODO — MVP Acto I (Experiencia Continua en `criogenia.tscn`)

Objetivo: Completar un primer nivel continuo (sin cambios de escena) con plataformas móviles, barandas, tubos conectores, conveyor, objetivos claros, fuerzas de viento, cajas apilables y sistema de muerte/respawn.

## Plan del día — 2025-12-02
1) BGM mínimo: usar `autoload/AudioManager.gd` en `Menu.tscn` y `criogenia.tscn` (tema menú: `assets/music/Orbital Descent.mp3`; nivel: `assets/music/Rust and Ruin.mp3`). Estado: listo (ambas escenas reproducen BGM via `LevelBGM.gd`).
2) Integrar `WindZone.tscn` en `criogenia.tscn` y calibrar `lift_force`/`max_speed`. Estado: primera WindZone integrada; pendiente tuning fino.
3) Kill/Respawn + Checkpoints: `KillZone.gd` + `KillZone.tscn` bajo el nivel; extender `PlayerManager.gd` con `last_checkpoint_transform` y `respawn()`; `Checkpoint.tscn` que notifique al manager. Estado: funcional (muerte/respawn, último checkpoint, música cambia en muerte y reinicia al respawn).


## Dejamos para mañana:
	
4) Barandas y conectividad: crear `GuardrailSegment.tscn` y `TubeConnector.tscn`, colocarlos en bordes críticos y unir alas para backtracking.
5) Objetivo y cajas: `GoalBeacon.tscn` (fin del recorrido) y `PushableBox.tscn` (apilado 2–3 cajas).
6) Integrar “Cargol”: `scenes/common/Cargol.tscn` (prop/NPC simple) y ubicarlo en `criogenia.tscn`.
7) Spawn cinematográfico: transición de cámara y bordes negros reutilizables.
  - Refactorizar bordes negros de para reutilizarlos al entrar, en un hud o en cinematicas.
  - Añadir parámetros en `scripts/SceneSpawn.gd` para duración/intensidad y resetear ángulo de cámara al respawn.
- [ ] SceneManager y Loading Screens
  - Añadir `SceneManager` (autoload) para gestionar pantallas de carga y transiciones.


## Prioridad Alta
- [ ] Plataformas con barandas
  - Crear `scenes/common/GuardrailSegment.tscn` (StaticBody + Mesh modular) y rodear bordes de plataformas principales y móviles, dejando huecos de salto.
  - Integrar en `scenes/levels/act1/criogenia.tscn` (plataforma principal + `PuzzleZone`).
- [ ] Tubos conectores entre alas
  - Crear `scenes/common/TubeConnector.tscn` (CSGCylinder/CSGTorus + StaticBody) y conectar plataformas/alas para navegación y backtracking.
  - Añadir entradas/salidas legibles (anillos luminosos).
- [ ] Conveyor en plataforma principal
  - Implementar `scripts/Conveyor.gd` + `scenes/common/Conveyor.tscn`. Estado: listo (escena y script existen; instancia presente en `criogenia.tscn`).
  - Empuje tangencial configurable (`push_velocity`), ancho/longitud de banda y material con flechas.
  - Colocar en la primera plataforma principal. Estado: presente; pendiente de calibración fina.
- [ ] Objetivo de alto contraste
  - Crear `scenes/common/GoalBeacon.tscn` (Mesh + material emisivo/color contrastante + `Area`).
  - Al entrar en el `Area`, marcar objetivo: abrir compuerta, encender baliza o registrar progreso.
- [x] Vientos/Fuerzas ascendentes
  - Implementar `scripts/WindZone.gd` + `scenes/common/WindZone.tscn` (`Area`) que aplica fuerza vertical configurable a cuerpos dentro. Estado: listo (script y escena creados); falta colocar en `criogenia.tscn`.
  - Señalizar con partículas/flechas/sonido suave.
- [ ] Bloques apilables
  - `scenes/common/PushableBox.tscn` (`RigidBody`) con dimensiones estándar, fricción y masa para apilar/arrastrar.
  - Opcional: puntos de anclaje o “slots” guía para facilitar el apilado en MVP.
- [x] Muerte por caída
  - `scripts/KillZone.gd` (Area grande bajo zona jugable) ⇒ muerte inmediata.
  - Opcional: `FallDamage.gd` para muerte si velocidad vertical/altura excede umbral.
- [x] Respawn a estado viable
  - Extender `autoload/PlayerManager.gd` con checkpoints (`Checkpoint.tscn`) y snapshot de posición/rotación.
  - Al morir, respawn en el último checkpoint seguro.
  - Estado: `KillZone` y `Checkpoint` implementados; `PlayerManager` extendido con `respawn()` y checkpoints. Falta colocar en `criogenia.tscn`.
- [ ] Spawn cinematográfico y cutscenes
  - `scenes/common/ScreenBorders.tscn` para bordes negros reutilizables (Kill/Spawn/Cutscenes).
  - `scripts/SceneSpawn.gd` con exports para duración, grosor de bordes y transición de cámara.
  - Al respawn, resetear el ángulo/rotación de cámara.

## Integración con lo existente
- [ ] Ajustar `scripts/MovingPlatform.gd` si es necesario para transportar al jugador de forma estable (comprobar colisiones en bordes).
- [x] Añadir `KillZone` y `WindZone` en `criogenia.tscn` (primera ala: plataformas + conveyor; segunda ala: salto con viento + cajas apilables). Estado: colocados; pendiente de calibrar posiciones/valores.
- [ ] Materiales: usar `materials/interior/*` y `addons/kenney_prototype_textures` (marcas de dirección para conveyor/trayectorias).

## Convenciones de capas de colisión (propuesta MVP)
- Player (`KinematicBody`): layer 1, mask: 2 (entorno), 3 (plataformas móviles), 4 (conveyor), 5 (wind), 6 (checkpoints), 7 (kill), 8 (cajas). No debe colisionar con layer 9 (cámara helpers).
- Entorno estático (suelo/estructuras): layer 2, mask: 1 (player), 8 (cajas).
- Plataformas móviles: layer 3, mask: 1 (player), 8 (cajas), 2 (entorno) — evitar que plataformas choquen entre sí: NO incluir 3 en su mask.
- Conveyor (Area): layer 4, mask: 1 (player), 8 (cajas) — aplica `push_velocity` sin colisionar físicamente.
- WindZone (Area): layer 5, mask: 1 (player), 8 (cajas).
- Checkpoint (Area): layer 6, mask: 1 (player).
- KillZone (Area): layer 7, mask: 1 (player), 8 (cajas) si queremos limpiar caídas.
- Cajas (`RigidBody`): layer 8, mask: 2 (entorno), 3 (plataformas), 8 (otras cajas) — NO mask 4/5/6/7 para evitar reacciones no deseadas; permitir lectura de fuerzas vía `Area` si es necesario con monitorables.
- Cámara helpers (raycasts/areas de cámara): layer 9, mask: 2 (entorno) — evitar interacción con player.

Acción: revisar cada escena (`MovingPlatform.tscn`, `Conveyor.tscn`, `WindZone.tscn`, `KillZone.tscn`, `Checkpoint.tscn`, `PushableBox.tscn`) y aplicar este mapeo para prevenir colisiones entre plataformas y filtrar interacciones.

## Nota de bug de cámara sobre Conveyor
- Síntoma: al pasar sobre el conveyor, la cámara parece girar cuando no debería; sólo debería hacerlo si el jugador cambia de dirección.
- Hipótesis: 1) La cámara está leyendo la orientación del `Player` influida por `external_velocity` del conveyor (p.ej., cálculo de forward via `velocity.normalized()`); 2) Un `Area` del conveyor afecta la máscara/capa de un `RayCast` de cámara; 3) `look_at`/`slerp` usa `global_transform.basis` del player que varía con fuerzas externas.
- Acciones sugeridas:
  - En `CameraTemplate.gd`, desacoplar orientación de cámara del `external_velocity`: base rumbo = input del jugador, no la velocidad total.
  - Filtrar capas para que helpers de cámara ignoren layer 4 (conveyor) y 5 (wind).
  - Clampear cambio de yaw según `dot(forward, desired_forward)` y aplicar suavizado con spring (ver plan de cámara abajo).
  - Verificar que el `AnimationTree` del player no esté rotando el `KinematicBody` por blend dependiente de velocidad.

## Plan de mejora de Cámara (siguiente paso)
- Spring-damper: implementar en `scripts/CameraTemplate.gd` un seguimiento con modelo masa-resorte-amortiguador para posición y yaw/pitch.
- Zoom dinámico por velocidad: ajustar distancia (`target_distance`) según magnitud de `player_velocity` (ignorar `external_velocity` del conveyor para determinación de zoom). Rango sugerido: 4.5–7.0 m.
- Límites y suavizado: limitar pitch/yaw, suavizar transiciones con `delta` y `critically damped` (ζ≈1, ω≈3–6).
- Colisión de cámara: raycast con layer 2 (entorno) únicamente; evitar que áreas dinámicas (4/5/6/7) afecten.
- Parámetros exportados: `base_distance`, `max_distance`, `speed_zoom_gain`, `spring_strength`, `damping_ratio`, `ignore_external_velocity` (bool).

Entrega: añadir estos exports a `CameraTemplate.gd` y validar en `criogenia.tscn` con conveyor y viento.

## Implementación técnica (archivos nuevos)
- [ ] `scenes/common/GuardrailSegment.tscn` — segmento 2m con `StaticBody` + `CollisionShape` (altura ~1m).
- [ ] `scenes/common/TubeConnector.tscn` — CSG + `StaticBody` con colisión cilíndrica; entradas con borde luminoso.
- [x] `scripts/Conveyor.gd` — aplica velocidad constante a `KinematicBody`/`RigidBody` dentro (por ejemplo, vector en tangente de banda). Exponer: `push_velocity`.
- [x] `scenes/common/Conveyor.tscn` — `Area` + `CollisionShape` + Mesh plano con textura de flechas.
- [x] `scripts/WindZone.gd` — aplica fuerza vertical; Exponer: `lift_force`, `max_speed`. Opción pulsante.
- [x] `scenes/common/WindZone.tscn` — `Area` + `CollisionShape` + partículas direccionales.
- [ ] `scenes/common/PushableBox.tscn` — `RigidBody` + `CollisionShape` + Mesh cúbico; fricción alta.
- [ ] `scripts/KillZone.gd` — al entrar, emitir señal de muerte al `PlayerManager`.
- [ ] `scenes/common/KillZone.tscn` — `Area` grande bajo plataformas.
- [ ] `scenes/common/Checkpoint.tscn` — `Area` + marcador visual; notifica a `PlayerManager`.
- [x] `scripts/KillZone.gd` — al entrar, emitir señal de muerte al `PlayerManager`.
- [x] `scenes/common/KillZone.tscn` — `Area` grande bajo plataformas.
- [x] `scenes/common/Checkpoint.tscn` — `Area` + marcador visual; notifica a `PlayerManager`.
- [ ] `scripts/GoalBeacon.gd` + `scenes/common/GoalBeacon.tscn` — activa objetivo y guarda progreso.
- [ ] `scripts/ScreenBorders.gd` + `scenes/common/ScreenBorders.tscn` — CanvasLayer con `TopRect`/`BottomRect` animables; API `show_borders()`/`hide_borders()`.
- [ ] `scripts/SceneSpawn.gd` — añadir exports de transición (`spawn_duration`, `border_thickness_pct`, `reset_camera_on_respawn`) y métodos `play_spawn_intro()` / `play_respawn_intro()`.

## Integración de audio y Cargol (low-hanging fruit)
- [x] Autoload `AudioManager.gd` registrado en `project.godot`.
- [x] Reproducir BGM en `Menu.tscn` (`Orbital Descent.mp3`).
- [x] Reproducir BGM en `criogenia.tscn` (`Rust and Ruin.mp3`).
- [ ] `scenes/common/Cargol.tscn` (prop/NPC simple) e integración en `criogenia.tscn`.
  - Nota: `scripts/LevelBGM.gd` creado para adjuntar a un nodo vacío del nivel.

## Pruebas y balance
- [ ] Ajustar velocidades (`MovingPlatform.speed`, `wait_time`) y curvas (`data/Curves/*.tres`).
- [ ] Conveyor: calibrar `push_velocity` para que requiera correcciones pero no frustre.
- [ ] Viento: `lift_force` que permita ascenso controlado con salto planeado.
- [ ] Cajas: comprobar apilado estable (2–3 cajas), sin jitter excesivo.
- [ ] KillZone/Respawn: morir fuera de límites siempre respawnea en el último checkpoint.

## Entregables del MVP
- [ ] `criogenia.tscn` con: plataformas con barandas, conveyor activo, un tubo conector a ala secundaria, zona de viento para ascenso, cajas apilables para resolver un acceso, objetivo de alto contraste que concluye el recorrido.
- [ ] Actualizar `README.md` con controles y rutas: cómo alcanzar la baliza/objetivo y cómo usar viento/cajas/conveyor.

## Cambios recientes
- [x] Ajustar transparencia del material en `WindZone` y añadir partículas.
- [x] Corregir interacción del conveyor con Elias.
- [x] Implementar efecto visual de "cerrar los ojos" en `KillZone`.
- [x] Cambiar música al morir y reiniciarla al hacer respawn.
- [x] Respawn accepts any key or button press.
- [x] Added "Offline" label to death screen.
- [x] WindZone: partículas billboard emisivas, distribución en volumen y sin gravedad.
- [x] Conveyor: shader más sutil (menos contraste/emisión) y empuje aplicado también a `RigidBody`.
