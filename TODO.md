🛠️ Backlog de Correcciones - Fin de Semana

A continuación se detallan los problemas críticos detectados en las últimas pruebas de estrés y tests deterministas.

1. Odyssey Script (OYS) - Error de Gravedad

Problema: Los scripts de OYS parecen estar inyectando una fuerza descendente anómala en el jugador.

Observación: El jugador no mantiene su altura o cae más rápido de lo normal durante la ejecución de comandos WAIT o FW.

Tarea: Revisar la integración de SessionManager con el motor de física cuando el input viene del buffer OYS.

2. Desplazamiento en Pendientes (Slopes)

Problema: El sistema de "snap" o el manejo de pendientes está fallando.

Observación: El personaje se queda trabado o no sube rampas que antes funcionaban.

Tarea: Verificar floor_max_angle en el controlador y el vector de movimiento en superficies inclinadas.

3. Resistencia al Movimiento

Problema: Sensación de pesadez o fricción excesiva "fantasma".

Observación: No se han tocado los valores de velocidad, pero el movimiento es lento.

Tarea: Revisar si hay algún Lerp de velocidad mal calculado o si la fricción de los PhysicsMaterial globales ha cambiado.

Nota: Priorizar la corrección de OYS, ya que impide validar los demás sistemas de forma automática.


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
