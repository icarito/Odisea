# FD-HOLO_RL_POLICY: Locomoción RL del ProgrammerHoloNPC

**Status:** Draft (integración inicial)
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-11-13

## Problem

La política RL de ANNA (PPO, `obs 13 -> MLP 128/128 tanh -> Discrete(8)`) ya se
exporta a JSON e infiere de forma determinista en GDScript
(`core_v2/agents/MLPPolicyInference.gd`, ver `test_anna_mlp_inference.gd`), pero
sólo se usaba para el jugador (env `core_v2/anna/AnnaInterface.gd` /
`core_v2/anna/client/anna_gym.py`). El NPC-holograma `ProgrammerHoloNPC`
(la "Programadora") se movía únicamente con lógica hand-authored
(`FOLLOW` / `MOVE_TO` / `ORBIT_GUIDE`).

Objetivo: que la política entrene también su locomoción de seguir/guiar, de forma
**opcional y reversible**, sin romper inmersión ni determinismo.

## Solución

Se agrega un controlador nuevo, `core_v2/agents/HoloPolicyController.gd`
(`Reference`, sin `class_name` para no tocar `project.godot`), que:

- carga los pesos con `MLPPolicyInference.load_from_json()`;
- construye la obs 13 y elige acción por **argmax** (desempate por menor índice);
- expone helpers puros y testeables (`build_observation`, `select_action`,
  `signed_angle_to_target`, `action_to_local_move`, `action_is_sprint`).

El NPC integra el controlador detrás de un flag:

- `export(bool) use_rl_policy = false` (default apagado → comportamiento actual intacto);
- nuevo `BehaviorMode.RL` y API explícita `start_rl_follow(target, duration)` /
  `start_rl_guide(pos, speed)`.

Con `use_rl_policy = true`, los modos `FOLLOW` / `MOVE_TO` / `ORBIT_GUIDE`
delegan su locomoción al controlador (así los llamadores existentes
`MachineLevel.say()` y `RingHubLightState.enter_machine_bay()` obtienen RL sólo
encendiendo el flag, sin editarlos). Con `false`, o si los pesos no cargan, corre
el código hand-authored de siempre.

### Contrato obs13 (espejo del env del jugador)

| idx | feature | rango |
|----|---------|-------|
| 0..7 | 8 rayos `clamp(d / 20, 0, 1)`, rayo *i* a `(360/8)*i`° en Y; 0 = forward (`-Z`) | 0..1 |
| 8 | `clamp(dist_objetivo / 50, 0, 1)` | 0..1 |
| 9 | `ángulo_con_signo / PI` (`forward x to_target`.y < 0 ⇒ negativo) | -1..1 |
| 10 | `vel_local.x / 20` | -1..1 |
| 11 | `vel_local.z / 20` | -1..1 |
| 12 | altura cruda `y` | libre |

Rayos: `PhysicsDirectSpaceState.intersect_ray` desde `_anchor_origin + (0,1,0)`
sobre el basis de control, sin nodos `RayCast` (el NPC es cinemático, sin
`CollisionShape`). `rl_collision_mask`/`rl_sensor_range` son export.

### Mapeo Discrete(8) → movimiento cinemático

| acción | nombre | efecto en el NPC |
|-------|--------|------------------|
| 0 | SteerOnly | sólo orientar hacia el objetivo |
| 1 | Forward | avanzar |
| 2 | SprintForward | avanzar a `rl_sprint_speed` |
| 3 | JumpForward | avanzar (salto colapsado) |
| 4 | StrafeLeft | desplazar a la izquierda |
| 5 | StrafeRight | desplazar a la derecha |
| 6 | JumpStrafeLeft | izquierda (salto colapsado) |
| 7 | JumpStrafeRight | derecha (salto colapsado) |

El holograma flota y no tiene física ni salto, así que el componente `jump` se
**colapsa al horizontal**. El movimiento se aplica con la misma velocidad/lerp
que ya usaba el NPC (`_apply_hover_transform`, `_face_position`), y el "assisted
steering" (orientar siempre hacia el objetivo) replica el del env del jugador.

### Convención de forward

El frente visual del NPC es el **+Z del `Pivot`** (coordenadas del proyecto con
base de 180°, AGENTS §11.1), mientras el contrato RL usa **−Z** como forward. El
basis de control se construye como `Basis(UP, pivot.yaw + PI)` para que
`-basis.z` coincida con el frente visual y con la asistencia de steering.

### Determinismo

Inferencia en floats de 64 bits, argmax con desempate fijo, sin `randf`, sin
`Tween`, sin reloj de pared; todo en `_physics_process`. El NPC es visual
(cinemático), no pertenece a `replay_sync`; el contrato de señales
(`arrived` / `script_finished` / `speech_finished`) no cambia.

## Tests

- `core_v2/tests/test_holo_rl_policy.gd`: builder de obs (dims/rangos), mapeo de
  acciones, signo del ángulo, determinismo de acción y de **traza completa**
  (`test_npc_rl_trace_is_reproducible`), convergencia a objetivo
  (`test_npc_rl_guide_converges_to_point`) y fallback con flag apagado.
- `core_v2/tests/test_anna_mlp_inference.gd`: inferencia MLP contra golden (sin cambios).
- `core_v2/tests/test_programmer_holo_npc.gd`: sin regresiones (comportamiento hand-authored intacto).

## Evidencia visual

Harness `core_v2/tests/HoloRLLab.tscn` + `HoloRLLab.gd` (960x540, editor con display):

```
"$(sh tools/godot_bin.sh)" --path . res://core_v2/tests/HoloRLLab.tscn --no-window
```

Corrida de verificación: RL ON → `mode=6`, última acción 2, converge de
`dist=13.72` a `dist=0.37`; RL OFF → `mode=4` hand-authored, termina en
`dist=5.25`. Capturas en `test_output/holo_rl/`.

## Pendiente

- **Puente Discrete(8) → `InputDataV2` del lado jugador** (otro trabajo; no toca
  `PlayerControllerV2`/`MultiToolV2`).
- La política actual tiene fuerte sesgo a `SprintForward` (acción 2) con obs
  "sin obstáculos"; para seguir/guiar con obstáculos conviene re-entrenar con
  shaping para ese contexto o añadir capas de seguridad tipo hazard telegraph
  (ver constraints de hazards/trampas).
- Evaluar 960x540 con confirmación humana de QA visual (el modelo no ve imágenes).
- Exponer `use_rl_policy` en el Inspector de las escenas que instancian el NPC,
  si se decide usar RL en una ruta concreta de gameplay.
