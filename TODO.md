# TODO — MVP Odisea (2026-01-29)

## Pendientes principales
- Reimplementar BGM mínimo (`autoload/AudioManager.gd` en Menu y criogenia)
- Reimplementar WindZone (scenes/common)
- Reimplementar multiplayer split-screen (core_v2)
- Plataformas con barandas (`scenes/common/GuardrailSegment.tscn`)
- Tubos conectores entre secciones (`scenes/common/TubeConnector.tscn`)
- Objetivo de alto contraste (`scenes/common/GoalBeacon.tscn`)
- Spawn cinematográfico y cutscenes (`scenes/common/ScreenBorders.tscn`, `scripts/SceneSpawn.gd`)
- Obstáculos ambientales: Fugas de plasma (`scenes/common/PlasmaLeak.tscn`)
- Drones DDC patrulleros (`scenes/common/DDCDrone.tscn`)
- Ventanal gigante y nebulosa (escena final)
- Diálogos narrativos con IA (DialogueManager, JSON, AudioStreamPlayer3D)
- Integrar "Cargol" (`scenes/common/Cargol.tscn`)

## QA y balance
- Medir cobertura y limpiar pendientes menores

## Referencias
- Estructura y normas: ver `README.md` y `AGENTS.md`.
- Features implementados: ver `docs/canon/`.

## Capas de colisión (referencia)
- Player: layer 1, mask: 2 (entorno), 3 (plataformas móviles), 4 (conveyor), 5 (wind), 6 (checkpoints), 7 (kill), 8 (cajas). No colisionar con layer 9 (cámara helpers).
- Entorno estático: layer 2, mask: 1 (player), 8 (cajas).
- Plataformas móviles: layer 3, mask: 1 (player), 8 (cajas), 2 (entorno).
- Conveyor: layer 4, mask: 1 (player), 8 (cajas).
- WindZone: layer 5, mask: 1 (player), 8 (cajas).
- Checkpoint: layer 6, mask: 1 (player).
- KillZone: layer 7, mask: 1 (player), 8 (cajas).
- Cajas: layer 8, mask: 2 (entorno), 3 (plataformas), 8 (otras cajas).
- Cámara helpers: layer 9, mask: 2 (entorno).