# FD-274 T1: Determinismo de replay en el ascensor (brief para Jules)

## ⚠️ ANTES DE EMPEZAR — Godot 3 vía apt (obligatorio)

En Odisea SIEMPRE hay que instalar Godot 3 con `apt` antes de correr cualquier test.
El proyecto es **Godot 3.x** (`project.godot` con `config_version=4`), no Godot 4.
Verificá que `godot` (o `godot3` / `godot3-bin`) esté en el PATH y sea 3.x antes de
ejecutar el runner. Si no está, instalalo con apt y recién después corré los tests.

Runner de tests (GdUnit3): `./runtest.sh -a ./core_v2/tests/` (headless). El output
siempre se guarda en `./reports/gdunit_runner.log`; si no ves salida en terminal,
leé ese archivo (`grep -E "(PASSED|FAILED|ERROR|Total)" ./reports/gdunit_runner.log`).

## Contexto — qué está mal

El ascensor (`ElevatorController`) mueve la plataforma (`ElevatorPlatform`) y coordina
las puertas (`DualSlidingObjectV2`) con una cola de peticiones. Todo el sistema es
`replay_sync` (determinista, manejado por `SessionManager` que llama `step(dt)` con
paso fijo). PERO la secuencia de esperas está rota en términos de determinismo:

El problema está en `ElevatorController.gd`, **no en las puertas**. Las puertas ya son
deterministas (`anim_progress` avanza por `step(dt)` en `InteractableBaseV2`).

## Defectos concretos localizados

1. `ElevatorController._process_queue()` usa
   `yield(get_tree().create_timer(0.9), "timeout")` para esperar el cierre de puerta
   antes de mover la plataforma.
2. `ElevatorController._on_arrived()` usa
   `yield(get_tree().create_timer(1.0), "timeout")` antes de procesar la cola.
   - Ambos `yield` corren en **reloj de pared real** (SceneTree timer), NO en el bucle
     determinista `step(dt)` que `SessionManager` maneja. En replay, el input grabado
     avanza a paso fijo (`FIXED_DT`) pero estos timers avanzan con los frames reales →
     desfase acumulado y secuencia no reproducible.
3. `door_open_wait := 2.0` está **exportado pero nunca se usa**; los waits están
   hardcodeados (0.9s y 1.0s). El tuning exportado es letra muerta.
4. `get_snapshot()` / `_apply_snapshot()` guardan `requests`, `current_floor`,
   `target_floor`, `is_moving`, pero **NO capturan el estado de los `yield` en vuelo**.
   Si se restaura a mitad de una espera, el punto de reanudación del coroutine se pierde.

## Dirección del fix (sin código — vos lo implementás)

- Mover el timing de espera de puerta/cola **dentro del loop determinista**: reemplazar
  los `yield(create_timer(...))` por una máquina de estados con un contador de tiempo
  acumulado (`wait_remaining`) decrementado por `dt` fijo dentro de `step(dt)`.
  Usá `door_open_wait` como fuente de verdad del tuning (no volver a hardcodear).
- Serializar ese estado pendiente en el snapshot (`wait_remaining`, fase actual del
  estado) para que `restore_snapshot` reanude la espera exactamente donde estaba.
- No tocar `DualSlidingObjectV2` / `SlidingObjectV2` salvo que la espera de cierre
  deba depender de su `anim_progress` (en ese caso leé `anim_progress` en lugar de
  mantener un timer paralelo).

## Archivos implicados (referencia)

- `core_v2/props/ElevatorController.gd` (foco del cambio)
- `core_v2/components/ElevatorPlatform.gd` (KinematicBody, grupo `replay_sync`, `step(dt)`)
- `core_v2/props/elevator/MaintenanceElevator.gd` (integra movimiento en `step(dt)`)
- `core_v2/components/InteractableBaseV2.gd` (contrato de snapshot: `anim_progress`,
  `target_progress`, `is_active`, `is_used` — NO modificar salvo lectura)
- `core_v2/props/doors/ElevatorDoor.gd`, `core_v2/components/DualScalingObjectV2.gd`,
  `core_v2/components/SlidingObjectV2.gd` (solo lectura si hace falta)

## Reglas

- Godot 3.x / GDScript 1.x: `yield`, nunca `await`. Sin `@onready`.
- Determinismo: el timing debe vivir en `step(dt)`, no en `create_timer`.
- Composición sobre herencia; señales, no `get_parent()`.
- Cada componente < 200 líneas haciendo una sola cosa.

## Criterio de aceptación

1. La secuencia puertas→movimiento→espera es reproducible en replay (mismo input → mismo
   estado, sin depender del reloj de pared).
2. `door_open_wait` controla efectivamente la espera de puerta (ya no hay 0.9/1.0 hardcodeados).
3. `get_snapshot()`/`restore_snapshot()` reanudan una espera a mitad de camino sin salto.
4. `./runtest.sh -a ./core_v2/tests/` no rompe las pruebas existentes (especialmente
   `test_replay_prop_snapshots.gd`, que valida el snapshot roundtrip del ascensor).

Cuando termines, publicá el PR contra `main` con el spec y el diff. **No mergear sin OK explícito.**
