# Missing Features for Act 1 MVP — Especificación ampliada

Este documento recoge las funcionalidades prototipadas que deben reimplementarse en `core_v2` y proporciona notas de implementación concretas (suficientes para que un agente/implementador las lleve a código).

## Reglas generales de determinismo
- Todos los agentes sincronizables deben pertenecer al grupo `replay_sync`.
- Implementar `get_snapshot() -> Dictionary` y `restore_snapshot(data: Dictionary)` en nodos con estado mutable.
- Toda la lógica de simulación y movimiento debe ejecutarse en `_physics_process(delta)`.
- Los `restore_snapshot` no deben sobrescribir la fuente de verdad si no es necesario; preferir restaurar parámetros (tiempo, start_position, cycle_duration, etc.) y recalcular la posición desde esos parámetros.

## Conveyor (implementación y snapshot)
- Funcionalidad clave:
  - Aplicar `push_velocity` transformado al espacio mundo a cuerpos en el `Area`.
  - Para `Player`/Kinematic bodies: usar `set_external_velocity(world_push)` cada frame.
  - Para `RigidBody`: aplicar fuerza central con `add_central_force(world_push * rigid_force_multiplier)`.
  - Actualizar parámetros del `ShaderMaterial` para la visual del movimiento.
- Snapshot recomendado (mínimo):
  - `pos`: posición del nodo (world).  
  - `push_velocity`: vector de empuje en espacio local.  
  - parámetros visuales (colores, tiling, emission) si el look debe ser restaurable.
- Notas prácticas:
  - En `restore_snapshot`, si el nodo no está en el árbol, almacenar el snapshot y aplicarlo en `_ready`.
  - No depender de transformaciones no deterministas; usar `global_transform.basis.orthonormalized()` para convertir `push_velocity`.

## MovingPlatform (guía basada en `MovingPlatformV2.gd`)
Nota: Actualmente es el único obstáculo implementado y validado; úsese como referencia para el resto de sistemas.
Usar `MovingPlatformV2.gd` como referencia de comportamiento determinista. Implementación recomendada:

- Conceptos clave:
  - `movement_vector` o `start_pos` + `end_pos` como fuente única de verdad de la trayectoria.
  - `time_accumulator` (float) que avanza con `delta` y determina la posición mediante lógica ping-pong.
  - `pingpong_logic(value, half_cycle)` determinista para obtener progreso en [0..1].
  - `apply_easing(progress)` que aplica curvas o easing; para pruebas iniciales usar identidad (lineal) para máxima determinismo.
  - `linear_velocity` calculada como (pos_now - pos_prev)/delta y propagada a pasajeros con `set_external_velocity(linear_velocity)`.

- Snapshot recomendado (mínimo):
  - `pos` o mejor: `start_position` + `time` para que la posición se pueda recalcular.
  - `time` (`time_accumulator`).
  - `movement_vector`, `cycle_duration`, `start_delay`, `ease_type`.
  - `vel` (opcional) para diagnósticos.

- Regla importante para restaurar:
  - Evitar setear `global_transform.origin` directamente desde un `pos` si existe información de `time` y `start_position`; en su lugar, reconstruir `start_position` o recalcular `global_transform.origin` a partir de `start_position`, `movement_vector` y `time`.

- Uso de curvas:
  - Soporte para `acceleration_curve` (Curve resource) aplicado como multiplicador de velocidad: `speed_scale = acceleration_curve.interpolate(progress)`.
  - `use_curve_as_speed` vs `use_curve_as_position`: preferir aplicar la curva a la velocidad (safe para estabilidad) y mantener clamps `min_speed_scale` para evitar congelados.

- Señales y pasajeros:
  - Conectar `PassengerArea` a señales `body_entered`/`body_exited` o usar `get_overlapping_bodies()` en `_physics_process` (más seguro en tests headless).
  - Propagar `set_external_velocity(linear_velocity)` y si aplica `set_external_source_is_static(false)` para indicar fuente dinámica.

## WindZone
- Funcionalidad clave:
  - Aplicar un `gravity_override` en la dirección local `basis.y * lift` a cuerpos que entren.
  - Durante `_physics_process`, recalcular y reaplicar override en base a la velocidad actual del cuerpo para capear el efecto si excede `max_speed_along_wind`.
- Snapshot: parámetros de `lift`, `max_speed_along_wind` y posición si el zone se mueve.

## UI Overlay: Debug / Replay / Playback

- Requisitos funcionales:
  - Panel overlay accesible en escenas de test y en runtime que muestre controles de debug y reproducción.
  - Controles mínimos: `Play`, `Pause`, `Step`, `Rewind`, `Record`, `Save snapshot`, `Load snapshot`.
  - Indicadores: `current_time`, `frame`, `drift` (cuando aplique), y `active_replay_id`.
  - Toggle para mostrar colisiones, áreas y rutas de plataforma (debug visualization).

- Integración técnica:
  - Implementar como escena `Control` en `core_v2/view/ui/ReplayOverlay.tscn` con script `ReplayOverlay.gd` que use `SessionManager`/`ReplayManager` si existe.
  - Los botones deben emitir señales que el `SessionManager` consuma (`play`, `pause`, `step`, `rewind`, `record`).
  - El overlay debe poder activarse vía `ProjectSetting` o `Env var` para que los tests headless lo ignoren.

## KillZones y CheckZones (avance y cobertura)

- KillZone:
  - Área que detecta cuerpos que caen fuera del mapa y resetea/kill al player.
  - Debe exponer opciones: `respawn_point`, `instant_kill` (bool), `broadcast_death_event`.
  - Snapshot: no suele necesitarse salvo `respawn_point` dinámico.

- CheckZone (Checkpoint):
  - Área que al entrar registra el progreso del jugador y actualiza `last_checkpoint` en `PlayerManager` o `SceneSpawn`.
  - Debe emitir evento `checkpoint_reached(checkpoint_id)` y opcionalmente guardar snapshot parcial del jugador.
  - Tests: validar que al morir, el jugador reaparece en el `last_checkpoint` y que el replay reproduce ese comportamiento.

- Cobertura y métricas:
  - Añadir hooks para que los tests recopilen cobertura de zonas: número de `CheckZone` alcanzadas por replay, tiempos hasta checkpoint, y porcentaje de nivel cubierto.
  - Implementar contador simple en `SceneManager` o `TestHarness` que escriba resultados a `replays/coverage/<run_id>.json`.


## Player / Input: notas de implementación importantes
- Short jump (release early):
  - Implementar que si el jugador pulsa salto y suelta antes de alcanzar la altura máxima, la velocidad vertical se reduce (cut jump). Técnica:
    - On jump press: aplicar `jump_velocity`.  
    - Mientras `is_jumping` y `jump_button_released_early`: si `velocity.y > 0` entonces `velocity.y *= short_jump_multiplier` (ej. 0.5) o clamping a un `max_release_velocity`.
    - Registrar `jump_pressed_time` y `jump_released` para tests.

- Fricciones separadas:
  - `air_friction != movement_friction`: mantener constantes separadas para la resistencia aérea y la fricción de movimiento en suelo. Esto evita que el jugador pierda velocidad horizontal rápidamente en salto.

- Curvas de aceleración para movimiento:
  - Usar `Curve` resources para: aceleración de player (start/stop), respuesta del input, y para suavizar la camara (camera smoothing).
  - Para determinismo, documentar y serializar la curva o su referencia y preferir curvas con salida en [0..1].

## Tank Turn (reintroducir)
- Comportamiento esperado (resumen):
  - Rotación rápida en el lugar cuando el jugador mueve stick en dirección contraria a la orientación (giro tipo tanque).
  - Debe ser deterministicamente reproducible: la rotación se aplica en `_physics_process` con una velocidad angular dependiente del input y un timer.
- Implementación sugerida:
  - Añadir estados `is_tank_turning`, `tank_turn_timer`, `tank_turn_duration`, `tank_turn_rate`.
  - Cuando el ángulo entre facing_dir y input_dir supere umbral (ej. 120°) y el jugador esté en suelo, activar `is_tank_turning` y rotar con `rotation.y += tank_turn_rate * delta` hasta completar `tank_turn_duration`.
  - Incluir el estado de tank turn en snapshots si el jugador puede realizarlo durante replays.

## Touch controls y Droidpad JSON
- Formato mínimo de spec JSON que implementador debe soportar:
  - `buttons`: lista de { id, x, y, w, h, action, repeatable }
  - `sticks`: lista de { id, x, y, radius, mapped_axis }
  - `meta`: { screen_anchor, scale_mode }
- Implementación:
  - Parser que valida y normaliza coordenadas en DPI-independiente.
  - Emisión de eventos equivalentes a acciones de teclado/gamepad para `InputProviderV2`.

## Local Multiplayer (alcance MVP)
- Implementación mínima:
  - Soportar múltiples `InputProviderV2` vinculables a diferentes players (PlayerManager debe poder crear instancias con un `device_id` diferente).
  - Cada player debe pertenecer a `replay_sync` y exponer su `get_snapshot`/`restore_snapshot` para poder validar replays en modo local.

## Tests y validación de determinismo
- Casos inmediatos a añadir en `core_v2/tests`:
  - Movimiento básico del jugador (salto, short jump, walking) — comparar snapshot vs replay final.
  - Interacción con `MovingPlatformV2` (subir, permanecer y bajarse) — comprobar drift < threshold.
  - `Conveyor` empujando `RigidBody` y `Player` — comprobar que `set_external_velocity` y fuerzas producen el mismo resultado.
  - `WindZone` application/clear gravity override.
- Ejecución de tests (headless):
  - Usar `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd` y recolectar `drift`/logs.

## Checklist para el implementador (acciones concretas)
1. Revisar `core_v2/things/MovingPlatformV2.gd` y extraer las funciones `pingpong_logic`, `apply_easing`, `get_snapshot`, `restore_snapshot` como plantilla.
2. Implementar `Conveyor` con `get_snapshot`/`restore_snapshot` (ya añadido en `core_v2/sim/Conveyor.gd`).
3. Reimplementar `WindZone` en `core_v2/sim` siguiendo el patrón `get_snapshot`/`restore_snapshot` y `Area`-based body management.
4. Añadir `short_jump` y separar `air_friction` / `movement_friction` en `Player` core (`core_v2` input/player modules).
5. Reintroducir `Tank Turn` como estado determinista y añadirlo al snapshot del player.
6. Escribir tests unitarios y determinismo para cada caso (ver `core_v2/tests`).
