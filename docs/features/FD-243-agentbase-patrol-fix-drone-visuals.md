# FD-243: AgentBase PATROL Fix + Drone Visual Improvements

**Status:** Design → Jules
**Priority:** High
**Effort:** Small
**Created:** 2026-06-28
**Depends on:** PR #248 (FD-241/FD-242, `feature/FD-241-cargol-v2`)
**Branch base:** `feature/FD-241-cargol-v2`

## Problem

PR #248 (Cargol V2 + AgentBase + DDC drone) tiene CI rojo: 15 tests pasan, 1 falla. El fallo es `test_ddc_drone.gd > test_patrol_loop_with_pauses` (2ms). Además hay código duplicado entre Cargol y DDC, y oportunidades de mejora visual para los drones.

### Root cause del CI failure

AgentBase agregó `State.PATROL` al enum pero en `_calculate_wish_velocity()` trata PATROL idéntico a MOVE_TO:

```gdscript
State.PATROL:
    return _logic_move_to(target_position, dt)
```

`_logic_move_to()` está diseñado para "ir a X y terminar":
- Cuando distancia < 0.2 → `target_position = Vector3.ZERO` + `self.current_state = State.IDLE`
- Esto rompe el ciclo de patrulla de DDCDrone, que gestiona sus propias pausas y avances entre waypoints

**Flujo del bug:**
1. DDCDrone llega a waypoint → pone `_pause_timer = 2.0` correctamente
2. `.step(dt)` llama a AgentBase → `_logic_move_to` detecta distancia < 0.2 → fuerza `state = IDLE` y resetea `target_position`
3. El test `assert_vector3(drone.target_position).is_equal(Vector3(10, 0, 0))` falla

### Problemas secundarios

1. Solo 1 de 2 tests de DDC se ejecuta — `test_detection_logic_robust` nunca arranca porque el suite aborta tras el primer fallo
2. `test_player_stealth.gd` existe en el PR pero no está incluido en la suite de CI
3. Código duplicado: `_update_led()`, `_update_cone_scale()`, `_set_hum_pitch()` están copiados idénticos en CargolDroneV2.gd y DDCDroneV2.gd

## Solution

### 1. Fix: PATROL no transiciona a IDLE en AgentBase

Modificar `_logic_move_to` (o crear `_logic_patrol`) para que el estado PATROL:
- Al llegar al target (dist < 0.2): mantener velocidad cero, **no cambiar `current_state`**, no resetear `target_position`, no emitir `goal_reached`
- La subclase (DDCDrone) es dueña de las transiciones de PATROL

**Approach recomendado:** Agregar un parámetro booleano `hold_at_target: bool = false` a `_logic_move_to`:

```gdscript
func _logic_move_to(pos: Vector3, _dt: float, hold_at_target: bool = false) -> Vector3:
    var to_target = pos - global_transform.origin
    var dist = to_target.length()
    if dist < 0.2:
        if hold_at_target:
            return Vector3.ZERO  # Stay put, don't change state
        target_position = Vector3.ZERO
        self.current_state = State.IDLE
        emit_signal("goal_reached")
        return Vector3.ZERO
    # ... rest unchanged
```

Y en `_calculate_wish_velocity`:
```gdscript
State.PATROL:
    return _logic_move_to(target_position, dt, true)  # hold_at_target
```

### 2. Deduplicar helpers visuales → AgentBase

Mover a AgentBase como métodos base:

```gdscript
# AgentBase — métodos virtuales con implementación default
func _update_visuals():
    _update_led(Color.white)
    _update_cone_scale(1.0)

func _update_led(color: Color) -> void:
    # Implementación actual copiada de DDCDrone (con light opcional de Cargol)
    ...

func _update_cone_scale(scale: float) -> void:
    var cone = get_node_or_null("VisionCone")
    if cone and cone is Spatial:
        cone.scale = Vector3(scale, scale, scale)

func _set_hum_pitch(pitch: float) -> void:
    var hum = get_node_or_null("HumPlayer")
    if hum and hum is AudioStreamPlayer3D:
        hum.pitch_scale = pitch
```

CargolDroneV2 y DDCDroneV2 deben eliminar sus implementaciones locales y usar las de AgentBase (o override si necesitan comportamiento distinto).

### 3. Mejoras visuales — drones con personalidad

**DDCDrone — drone hostil:**
- LED de estado: rojo en patrulla (pulsante leve), rojo intenso rápido en ALERT, amarillo intermitente en SEARCH
- VisionCone: visible solo en ALERT (escala 1.5 con fade-in), invisible en patrulla/otros estados
- HumPlayer: pitch bajo en patrulla (0.9), sube a 1.5 en ALERT, oscila 1.0-1.3 en SEARCH
- Efecto de "luz de alarma" en ALERT: spotlight child con animación de giro rápido (como sirena visual)
- Material del mesh: metálico oscuro por defecto, con emission roja en ALERT

**CargolDrone — drone compañero:**
- LED de estado: azul suave por defecto, verde al seguir/interactuar, rojo solo en error
- StatusLight (luz puntual): intensidad 0.8 en idle, 1.5 al cargar/descargar
- Efecto de "campo de carga" alrededor del CargoAnchor: esfera translúcida azul que aparece solo cuando tiene cargo
- Idle animation: leve oscilación vertical (bob) + rotación lenta del mesh
- Trail sutil detrás del drone al moverse rápido

### 4. Test fixes

- Agregar `test_player_stealth.gd` al job de CI (`scripts/run_core_tests.sh` o donde esté la lista)
- Una vez arreglado el fix #1, verificar que `test_detection_logic_robust` corre también (deberían ser 2/2 en test_ddc_drone.gd)

## Files to Modify

- `core_v2/actors/AgentBase.gd` — Fix PATROL hold_at_target, agregar helpers visuales
- `core_v2/actors/DDCDroneV2.gd` — Eliminar métodos duplicados, agregar efectos visuales hostiles
- `core_v2/actors/CargolDroneV2.gd` — Eliminar métodos duplicados, agregar efectos visuales compañero
- `core_v2/tests/test_ddc_drone.gd` — Posible ajuste si cambia firma de métodos
- `scripts/run_core_tests.sh` (o CI config) — Agregar test_player_stealth
- `core_v2/actors/DDCDroneV2.tscn` — Agregar spotlight de alarma, configurar materiales
- `core_v2/actors/CargolDroneV2.tscn` — Agregar esfera de campo de carga, configurar idle animation

## Verification

1. `test_patrol_loop_with_pauses` pasa con distancia < 0.2 al waypoint
2. `test_detection_logic_robust` corre y pasa
3. `test_player_stealth` corre en CI
4. Los 16 tests originales pasan, más los nuevos
5. DDCDrone: LED rojo pulsa en patrulla, spotlight gira en ALERT, VisionCone desaparece en idle
6. CargolDrone: campo azul visible con cargo, desaparece sin cargo, bob idle visible
7. Sin código duplicado entre Cargol y DDC para helpers visuales
8. Assets exportan correctamente (asset-integrity check CI)
