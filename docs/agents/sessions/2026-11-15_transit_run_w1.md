# Sesión 2026-11-15 · Transit-Run fase 1 · W1 (flow metrics)

## Objetivo

Primera pista de "Transit-Run" (plataformero 3D de parkour cinético): medir EN EL MOTOR las
constantes físicas reales del jugador para que los niveles generados por WFC se deriven de
ellas. La ruta principal se calibra al 70–80% del alcance máximo (`H_max`, `D_max`); el 90–100%
y el uso de gloo/catenaria quedan para desvíos opcionales. Regla de oro: la ruta principal
**nunca** se bloquea con puzles obligatorios.

## Alcance y decisiones cerradas

- Unificar con FD-322 (bahía radial centrífuga): el contrato lo consumen el laberinto de
  MachineBay (`MachineBayLabyrinthStreamer`) y `bay_vertical` (anillo centrífugo). Por eso
  **toda métrica se expresa como función de `g`** (`g_eff = ω²·r` en el anillo).
- En zonas Transit-Run se corre por defecto; ruta principal a `v_run`.
- `salto → roll → salto` es técnica de habilidad del tramo 90–100%; nunca requisito principal.
- **Nota**: `docs/features/FD-322*` **no existe** en el repo; los más cercanos son FD-306
  (radial) y FD-320 (bahía de máquinas). Igual se respetó la unificación con MachineBay y el
  anillo.

Ampliación de alcance pedida por el orquestador durante la sesión: además del doc y el test, se
es dueño de `core_v2/systems/flow/FlowMetrics.gd` (fuente única de constantes). Se deja
`core_v2/systems/flow/FlowRouteValidator.gd` (otra pista) intacto; consume `FlowMetrics.metrics()`.

## Entregables

| Archivo | Qué es |
|---|---|
| `core_v2/systems/flow/FlowMetrics.gd` | Fuente única: lee constantes de `Pilot_v2.tscn` y expone funciones puras de `g`/tick + `metrics()` (dict para el validador). Sin `class_name` (se consume con `preload`). |
| `core_v2/tests/test_flow_metrics.gd` | GdUnit: mide `H_max`, `H_tap`, `t_air`, `D_max` corriendo/caminando, arranque, frenado, roll-jump y alcance de cornisa a **60 Hz y 30 Hz** con input real; exporta JSON y verifica el doc. |
| `core_v2/tests/test_flow_metrics.oys` | OYS: verificación en el motor al tick por defecto (60 Hz), leyendo constantes de la escena. |
| `docs/canon/WFC_FLOW_METRICS.md` | Doc canónico: contratos, umbrales, etiquetas de chunk, validación por semilla, anillo `g_eff(r)`, rarezas físicas. |

## Método de medición

- Constantes LEÍDAS de la escena (`FlowMetrics.from_pilot_node`), no hardcodeadas.
- Input real por las acciones del `InputMap` que lee el `InputProviderV2` del propio
  `PlayerControllerV2` (`Input.action_press`), sin tocar velocidades privadas.
- Avance por **frames reales del motor** (`yield physics_frame`) con `Engine.iterations_per_second`
  fijado a 60/30. Se descartó el stepping manual (`step()` en bucle): fuera del frame de física
  `move_and_slide` usa el delta real y no es reproducible (medido: la altura se duplicaba y
  variaba entre corridas).
- La cornisa se mide con frames reales porque el auto-hang depende del solape del `InteractArea`,
  que solo actualiza el servidor de física.

## Evidencia (medido vs analítico)

| Métrica | Analítico | 60 Hz | 30 Hz |
|---|---|---|---|
| `H_max` | 3.571 | 3.660 | 3.755 |
| `H_tap` | 2.041 | 2.133 | 2.355 |
| `t_air` | 1.429 | 1.433 | 1.433 |
| `D_max` corriendo | 10.00 | 10.04 | 10.04 |
| `D_max` caminando | 2.857 | 2.855 | 2.876 |
| arranque | 0.817 | 0.875 | 0.933 |
| frenado | 0.817 | 0.758 | 0.700 |
| roll-jump | — | 10.29 (roll 9.29 m/s) | 10.41 |
| cornisas (alcance) | 5.171 | 5.160 | 5.255 |

Rarezas documentadas con evidencia: en el aire (sin input) casi no se pierde velocidad
(`air_friction 5` vs `ground_friction 30`); con input la velocidad se **redirige** a `v_run`
(por eso `d_max_run ≈ v_run·t_air`); el tick bajo infla `H_max` (+2.6%); el roll casi no aumenta
el alcance (+2.5%, no +33%).

## Validación

- `./runtest.sh -a ./core_v2/tests/test_flow_metrics.gd` → verde.
- `./runtest.sh --oys test_flow_metrics` → verde (PASS 1 y PASS 2).
- `pytest tests/test_odisea_runner.py -k test_flow_metrics` → verde (nodo GdUnit).

## Pendiente / próximo

- **Sebastián debe aprobar `docs/canon/WFC_FLOW_METRICS.md`** antes de la fase 2.
- Fase 2: `FlowRouteValidator.gd` (otra pista) consume `FlowMetrics.metrics()` y valida semillas.
- `docs/features/FD-322` no existe: si la fase 2 lo necesita, crearlo/enlazarlo.
