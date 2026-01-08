
# TODO — Limpieza y MVP Acto I (2026)

## Sesión 1: Limpieza de legacy y tests (✅ Completada)
- [x] Eliminar archivos legacy y tests fuera de `core_v2` — legacy_archive/, tests/, scripts/replay, scripts/multiplayer, scripts/utils, scripts/ui, scripts/tools, PlayerController.gd, etc.
- [x] Limpiar referencias en project.godot — solo SessionManager y AudioManager/SceneManager
- [x] Correr tests con `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd` y validar estado — PASS (drift=0.000009)
- [x] Mover archivos orphans detectados a `archive/orphans_20260107/` — PlayerTrail.tscn, Checkpoint.tscn (experimental), run_replay.gd, objImportMeshFix.gd, splash_bg_color.png
- [x] Validar que SixtyFour, retro_scifi, default_acceleration_curve, WindZoneGradient siguen en uso

## Sesión 2: Refactor y housekeeping (✅ Completada)
- [x] Limpiar autoloads no usados (AudioSystem, GameGlobals, GameConfig, PlayerManager, InputState, FixedPoint, TouchCounter, UIManager)
- [x] Eliminar assets, escenas y scripts no referenciados — scan completado, solo orphans confirmados archivados
- [ ] Refactorizar código para consistencia y actualizar documentación en ./docs/

## Sesión 3: Integración y features MVP

**SISTEMAS QUE REQUIEREN REIMPLEMENTACIÓN TRAS REFACTOR:**
- [ ] Reimplementar BGM mínimo (`autoload/AudioManager.gd` en Menu y criogenia)
- [ ] Reimplementar Kill/Respawn + Checkpoints (`KillZone.tscn`, `Checkpoint.tscn`, lógica de respawn)
- [ ] Reimplementar Conveyor y WindZone (core_v2/sim y scenes/common)
- [ ] Reimplementar multiplayer split-screen (core_v2)

**OBSTÁCULO IMPLEMENTADO Y VALIDADO (REFERENCIA):**
- ✅ `MovingPlatformV2.gd` — Sistema de plataformas móviles determinista con snapshots, test de determinismo pasando (drift < 0.000009)

**NUEVAS FEATURES MVP:**
- [ ] Plataformas con barandas (`scenes/common/GuardrailSegment.tscn`)
- [ ] Tubos conectores entre secciones (`scenes/common/TubeConnector.tscn`)
- [ ] Objetivo de alto contraste (`scenes/common/GoalBeacon.tscn`)
- [ ] Bloques apilables (`scenes/common/PushableBox.tscn`)
- [ ] Spawn cinematográfico y cutscenes (`scenes/common/ScreenBorders.tscn`, `scripts/SceneSpawn.gd`)
- [ ] Obstáculos ambientales: Fugas de plasma (`scenes/common/PlasmaLeak.tscn`)
- [ ] Drones DDC patrulleros (`scenes/common/DDCDrone.tscn`)
- [ ] Ventanal gigante y nebulosa (escena final)
- [ ] Diálogos narrativos con IA (DialogueManager, JSON, AudioStreamPlayer3D)
- [ ] Integrar "Cargol" (`scenes/common/Cargol.tscn`)
## Sesión 3: Integración y features MVP
- [ ] Plataformas con barandas (`scenes/common/GuardrailSegment.tscn`)
- [ ] Tubos conectores entre secciones (`scenes/common/TubeConnector.tscn`)
- [ ] Objetivo de alto contraste (`scenes/common/GoalBeacon.tscn`)
- [ ] Bloques apilables (`scenes/common/PushableBox.tscn`)
- [ ] Spawn cinematográfico y cutscenes (`scenes/common/ScreenBorders.tscn`, `scripts/SceneSpawn.gd`)
- [ ] Obstáculos ambientales: Fugas de plasma (`scenes/common/PlasmaLeak.tscn`)
- [ ] Drones DDC patrulleros (`scenes/common/DDCDrone.tscn`)
- [ ] Ventanal gigante y nebulosa (escena final)
- [ ] Diálogos narrativos con IA (DialogueManager, JSON, AudioStreamPlayer3D)
- [ ] Integrar “Cargol” (`scenes/common/Cargol.tscn`)
- [ ] Reimplementar BGM mínimo (`autoload/AudioManager.gd` en Menu y criogenia)
- [ ] Reimplementar Kill/Respawn + Checkpoints (`KillZone.tscn`, `Checkpoint.tscn`, lógica de respawn)
- [ ] Reimplementar Conveyor y WindZone (core_v2/sim y scenes/common)
- [ ] Reimplementar Plataformas móviles (`MovingPlatformV2.gd` y test de determinismo)
- [ ] Reimplementar multiplayer split-screen (core_v2)

## Sesión 4: QA y balance
- [ ] Pruebas de apilado de cajas y respawn en checkpoints
- [ ] Validar entregables del MVP en `Criogenia.tscn`
- [ ] Medir cobertura y limpiar pendientes menores

## Convenciones de capas de colisión (referencia)
- Player (KinematicBody): layer 1, mask: 2 (entorno), 3 (plataformas móviles), 4 (conveyor), 5 (wind), 6 (checkpoints), 7 (kill), 8 (cajas). No colisionar con layer 9 (cámara helpers).
- Entorno estático: layer 2, mask: 1 (player), 8 (cajas).
- Plataformas móviles: layer 3, mask: 1 (player), 8 (cajas), 2 (entorno) — evitar choques entre plataformas.
- Conveyor (Area): layer 4, mask: 1 (player), 8 (cajas).
- WindZone (Area): layer 5, mask: 1 (player), 8 (cajas).
- Checkpoint (Area): layer 6, mask: 1 (player).
- KillZone (Area): layer 7, mask: 1 (player), 8 (cajas).
- Cajas (RigidBody): layer 8, mask: 2 (entorno), 3 (plataformas), 8 (otras cajas).
- Cámara helpers: layer 9, mask: 2 (entorno).