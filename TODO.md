
# TODO — Limpieza y MVP Acto I (2026)

## Sesión 1: Limpieza de legacy y tests
- [ ] Listar y eliminar archivos legacy y tests fuera de `core_v2` (legacy_archive, tests/, scripts/legacy, autoloads no usados)
- [ ] Confirmar borrado y limpiar referencias en project.godot
- [ ] Correr tests con `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd` y validar estado

## Sesión 2: Refactor y housekeeping
- [ ] Limpiar autoloads y scripts no usados por core_v2
- [ ] Eliminar assets, escenas y scripts no referenciados
- [ ] Refactorizar código para consistencia y actualizar documentación en ./docs/

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