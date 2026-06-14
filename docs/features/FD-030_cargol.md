# FD-030: Cargol — Dron Asistente

> Documento de feature colaborativo (Sebastian + Opus + Odiseo).
> Detalla qué es Cargol, qué hace hoy, qué proponemos agregar,
> y los contratos de determinismo que no se pueden romper.
> Las decisiones abiertas van como `[DECIDIR]`.

**Status:** Draft  
**Acto:** I — Vertical Slice  
**Relacionado:** GDD_v3, PushableBox, core_v2, CargolDroneV2, PR #198, PR #199  

---

## 0. Propósito y alcance

Cargol es el dron compañero no-piloteable de Elías. Este FD cubre tres capacidades
encadenadas: **movimiento/seguimiento** (ya implementado), **carga de objetos**
(implementado en modo clamp rígido), y la familia **tether → winch → polea/contrapeso**
(propuesta post-VS). También define la **capa de comando del player**.

Lo que queda explícito SIN decidir: el reparto lógica/visual de `CargolDroneV2`,
el modo de carga para el VS, y la arquitectura del punto de redirect (§12).

---

## 1. Estado actual (implementado)

`CargolDroneV2` es un `KinematicBody` con `class_name`.

### API pública

| Método | Qué hace |
|--------|----------|
| `move_to(position: Vector3)` | Vuela directo a una posición |
| `follow_path(path: NodePath)` | Sigue una curva `Path` |
| `follow_target(target: Node, distance)` | Sigue a un nodo manteniendo distancia |
| `return_to(position)` | Vuelve a home |
| `set_velocity(vector: Vector3)` | Control manual de velocidad |
| `stop()` | Frenar en seco |
| `pickup(target_node_path)` | Agarra un `RigidBody`, lo reparenta al `CargoAnchor` |
| `release(impulse: Vector3)` | Suelta el objeto con impulso |

### Integración level design

- **`CargolController.gd`** — palanca → `follow_target(player)` / `return_to(home)`
- **`CargolDroneProp.gd`** — wrapper PropZoo equivalente

### Lo que NO existe hoy

- Target navegable por nombre — todo es posición absoluta o `NodePath`
- Modo tethered/winch — `pickup` solo reparenta (clamp rígido)
- Comando directo del player — Cargol se dispara por interactables

---

## 2. Fantasía y rol

Cargol es **esencial pero dependiente**: el player atraviesa el mundo *a través* de
Cargol sin que Cargol sea piloteable. Elías no se vuelve autónomo ni poderoso por
tener a Cargol; gana posibilidad a costa de coordinación.

Restricción de tono: cualquier capacidad de movilidad (hook, swing) se diseña **no**
para disolver la vulnerabilidad ni el sigilo.

---

## 3. Sistema de carga — dos modos

### 3.1 Clamp rígido (ACTUAL — VS)
`pickup()` reparenta el `RigidBody` al `CargoAnchor`. La caja viaja solidaria a
Cargol. Simple, sin oscilación.

### 3.2 Tethered / Winch (PROPUESTO — post-VS)
La caja cuelga de un cable. Oscila (péndulo), conserva momentum. **No** es
reparenting: es un constraint de cable resuelto por un solver determinista (§5).

`[DECIDIR]` — Modo de carga para el VS: solo Clamp. Tethered va al backlog.

### 3.3 Máquina de estados de la caja

```
Free ↔ Held(Clamp) ↔ Tethered ↔ Counterweight
```

Cada arista: hand-off determinista + snapshot. `Counterweight` = caja atada a polea (§7).

---

## 4. Verbos y mapeo al código

| Verbo | Estado | API / sistema |
|-------|--------|---------------|
| Mover / volar | Implementado | `move_to`, `follow_path`, `set_velocity`, `stop` |
| Seguir | Implementado | `follow_target`, `return_to` |
| Cargar (clamp) | Implementado | `pickup` / `release` |
| Cargar (tether) | Propuesto | solver de constraints (§5) |
| Anclar como polea | Propuesto | solver + provider de redirect |

---

## 5. El solver de constraints determinista (PROPUESTO — post-VS)

El swing del payload, el swing de Elías (§6) y la polea/contrapeso (§7) **son la
misma cosa** — masas unidas por constraints de cable. No son tres sistemas: son
tres configuraciones de un solo solver.

Requisitos:
- Modelo propio paso fijo (Verlet + constraint de distancia), **no** `PinJoint`/`RigidBody`
- Orden de iteración fijo, conteo fijo
- Provider de redirect como abstracción

`[DECIDIR]` — Provider: anclaje fijo primero (más barato, más autorable). Cargol-polea después.

---

## 6. Hook de Elías (PROPUESTO — post-VS)

Cargol ancla y Elías rapela/se balancea de ese tether. Reusa el solver de §5.

- Independiente del sistema de carga (código separado, componen vía solver)
- Gating de tono: anclajes designados, NO movimiento libre Spider-Man

`[DECIDIR]` — Interacción con sigilo: ¿balancearse detecta DD?

---

## 7. Puzzles de poleas (PROPUESTO — post-VS)

Caja como lastre/contrapeso. Gramática: masa, geometría de anclajes, largo de cable.
**Un solo puzzle de prueba en backlog** — no entra al VS.

---

## 8. Contratos de determinismo (CRÍTICO)

1. **IK puramente cosmético**, downstream del estado lógico
2. **Trigger por proximidad lógica**, nunca por collider del end-effector
3. **`pickup`**: la caja debe seguir el transform lógico, no el visual → **ROTO** (#200)
4. **`release`**: el impulso debe derivarse de velocidad canónica → **ROTO** (#201)
5. **`move_and_slide`**: same-platform OK, cross-platform riesgo documentado (#202)
6. Separación lógica/visual → **no existe** (#203)
7. **Solver**: paso fijo, orden fijo, snapshot en reposo
8. **Múltiples actores sobre caja**: orden fijo de aplicación de fuerzas
9. **Sensibilidad a floats del péndulo**: fixed-point si se necesita cross-platform

---

## 9. Capa de comando del player (PROPUESTO)

El player **no pilotea** a Cargol. Le da **órdenes contextuales**.

### VS mínimo

| Comando | Condición | Implementación |
|---------|-----------|----------------|
| Seguir | Default / tras terminar tarea | `follow_target` |
| Quieto | Cargol idle | `stop()` |
| Ir a target | Mira interactuable con marker | `move_to(target)` + (#204) |
| Cargar / Soltar | Caja en rango | `pickup` / `release` |

**Input mapping tentativo:**
- Tap C → toggle Seguir ↔ Quieto
- Tap C con retícula sobre target → comando contextual (ir / cargar)
- Menú radial post-VS

`[DECIDIR]` — Plataforma primaria del VS sesga el diseño de input. Empezar con teclado+mouse.

---

## 10. Targeting: markers + enumeración

- **MarkerSystem** (PR #199): screen-space overlay, labels
- **TargetRegistry** (#204): world-space data para Cargol

Ambos se alimentan del mismo `MarkerConfig` + `InteractableEntity`, pero son capas
independientes. YAGNI: con 5-10 waypoints en el VS, array ordenado alcanza.

---

## 11. Morfología / IK (referencia, no spec)

- **Armless (VS)**: caja sostenida por campo/pinza magnética. Cero IK. Barato.
- **Con brazos (post-VS)**: 2 manipuladores, IK 2-huesos (ley de cosenos). Evitar `SkeletonIK`.

---

## 12. Decisiones pendientes

| # | Decisión | Estado |
|---|----------|--------|
| 1 | Separación lógica/visual de CargolDroneV2 | `[DECIDIR]` — Issue #203 |
| 2 | Modo de carga VS: solo Clamp | `[DECIDIR]` — Recomendado Clamp |
| 3 | Provider de redirect: anclaje fijo primero | Diferible |
| 4 | Morfología: armless en VS | Recomendado |
| 5 | Float vs fixed-point para swing | Post-VS |
| 6 | Hook ↔ sigilo / DD | Post-VS |
| 7 | Plataforma primaria: teclado+mouse | Recomendado |
| 8 | ~10 waypoints en VS | YAGNI, sin query espacial |
| 9 | Puzzle de polea: fuera del VS | Backlog |

---

## 13. Issues dependientes (pre-requisitos)

| Issue | Título | Bloquea |
|-------|--------|---------|
| [#200](https://github.com/icarito/Odisea/issues/200) | ✅ RESUELTO — PR #208 mergeado | — |
| [#201](https://github.com/icarito/Odisea/issues/201) | ✅ RESUELTO — PR #208 mergeado | — |
| [#202](https://github.com/icarito/Odisea/issues/202) | move_and_slide: riesgo cross-platform | Replay garantías |
| [#203](https://github.com/icarito/Odisea/issues/203) | Monolito lógica+visual | Post-VS |
| [#204](https://github.com/icarito/Odisea/issues/204) | TargetRegistry inexistente | Comando contextual |
| [#205](https://github.com/icarito/Odisea/issues/205) | Sin capa de comando del player | Input de Cargol |

---

## 14. Orden de implementación (VS)

1. ✅ ~~**#200 + #201**: Fix determinismo de pickup/release~~ → PR #208 mergeado
2. **Tarea A**: TargetRegistry dentro de InteractionMarker — ver §15
3. **Tarea B**: Capa de comando tap-C contextual — ver §16
4. **Cargol integrado en Módulo Criogenia** con comandos funcionando

Post-VS: #203 (separación lógica/visual), solver de constraints, tethered mode, puzzle de polea.

---

## 15. Tarea Jules A — TargetRegistry

### Objetivo

Agregar a `InteractionMarker` (PR #199, `core_v2/Components/UI/InteractionMarker.gd`)
una API pública consultable para que Cargol y otros sistemas puedan enumerar
interactuables cercanos.

### API a implementar

```gdscript
# InteractionMarker.gd — nuevos métodos públicos

func get_targets_in_range(origin: Vector3, range: float) -> Array
# Retorna Array de Dictionary:
#   { spatial: Spatial, config: MarkerConfig, distance: float, state: int }
# Ordenado por prioridad (menor = más alta), luego por distancia.

func get_named_target(name: String) -> Spatial
# Busca un interactuable registrado cuyo config.label coincida exactamente.
# Retorna el Spatial o null.

func get_registered_count() -> int
# Útil para debug: cuántos interactuables hay registrados.
```

### Datos a exponer

El diccionario interno `_interactables` ya existe (mapea Spatial→MarkerConfig).
También existe `_states` con el estado por interactuable. La API simplemente los
recorre, filtra por distancia, ordena y retorna.

### Constraints

- Solo consulta datos lógicos (posición world-space, config, estado).
- NUNCA leer `unproject_position()` ni screen-space — eso es para UI, no para sim.
- Con ~10 waypoints en el VS, O(n) es suficiente. Sin estructuras espaciales.
- Debe funcionar aunque el marker esté HIDDEN (Cargol puede querer ir a un objeto
  aunque no se esté mostrando en pantalla).

### Archivos a modificar

| Archivo | Acción |
|---------|--------|
| `core_v2/Components/UI/InteractionMarker.gd` | Agregar 3 métodos públicos |
| `core_v2/tests/test_interaction_marker_system.gd` | Agregar tests para `get_targets_in_range` |

### Tests requeridos

1. `test_get_targets_in_range` — registrar 3 objetos a distancias 3, 6, 9. Llamar con range=5. Asertar que solo retorna los 2 más cercanos.
2. `test_get_named_target` — registrar objeto con label "Consola OD-02". Buscar por nombre. Asertar que retorna el Spatial correcto.
3. `test_get_targets_respects_priority_order` — 3 objetos misma distancia, prioridades 5, 1, 3. Asertar orden [1, 3, 5].

---

## 16. Tarea Jules B — Capa de comando del player

### Objetivo

El player puede dar órdenes a Cargol con la tecla C, sin menú radial.

### Comportamiento

| Input | Condición | Acción |
|-------|-----------|--------|
| Tap C | Sin target bajo la mira | Toggle Seguir ↔ Quieto |
| Tap C | Retícula sobre interactuable con marker | `move_to(target.global_transform.origin)` |
| Hold C + Tap E | Caja en rango de Cargol | `pickup(caja)` |
| Hold C + Tap E | Cargol tiene caja cargada | `release(Vector3(2,0,0))` |

### Dónde vive el input handler

Crear `core_v2/actors/CargolPlayerInput.gd` como nodo hijo opcional de
`CargolDroneV2.tscn`. Si el nodo existe, Cargol acepta comandos del player.
Si no existe (ej: instancias manejadas por OYS script), Cargol funciona
normalmente con su API programática.

```gdscript
# CargolPlayerInput.gd
extends Node
# Hijo de CargolDroneV2. Traduce input del player a comandos del drone.

export(NodePath) var interaction_marker_path := "/root/InteractionMarker"
export(float) var command_range := 15.0

var _drone: CargolDroneV2
var _marker_system: Node
var _is_following := true

func _ready():
    _drone = get_parent() as CargolDroneV2
    _marker_system = get_node_or_null(interaction_marker_path)

func _input(event: InputEvent) -> void:
    if not _drone or event.is_echo(): return
    if event.is_action_pressed("cargol_command"):  # Tecla C
        _handle_tap_c()
    if event.is_action_pressed("interact") and Input.is_action_pressed("cargol_command"):
        _handle_hold_c_e()

func _handle_tap_c():
    # Primero: ¿hay un target bajo la mira?
    var target = _get_target_under_crosshair()
    if target:
        _drone.stop()
        _drone.move_to(target.global_transform.origin)
        return
    # Sin target: toggle seguir/quieto
    _is_following = not _is_following
    if _is_following:
        var player = _find_player()
        if player: _drone.follow_target(player, 3.0)
    else:
        _drone.stop()

func _handle_hold_c_e():
    if _drone._attached_node:
        _drone.release(Vector3(2, 0, 0))
    else:
        var box = _find_nearest_box()
        if box: _drone.pickup(box.get_path())

func _get_target_under_crosshair() -> Spatial:
    # RayCast desde la cámara al centro de la pantalla
    # Si colisiona con un Spatial que está registrado en InteractionMarker,
    # retornarlo. Si no, null.
    var camera = get_viewport().get_camera()
    if not camera: return null
    var from = camera.project_ray_origin(get_viewport().size * 0.5)
    var to = from + camera.project_ray_normal(get_viewport().size * 0.5) * command_range
    var space_state = camera.get_world().direct_space_state
    var result = space_state.intersect_ray(from, to)
    if result and result.collider:
        return result.collider as Spatial
    return null

func _find_nearest_box() -> Spatial:
    # Buscar PushableBox más cercana a Cargol
    var boxes = get_tree().get_nodes_in_group("pushable_box")
    var nearest: Spatial = null
    var nearest_dist := INF
    for box in boxes:
        var d = _drone.global_transform.origin.distance_to(box.global_transform.origin)
        if d < nearest_dist and d < 5.0:
            nearest_dist = d
            nearest = box
    return nearest

func _find_player() -> Node:
    var players = get_tree().get_nodes_in_group("player")
    return players[0] if not players.empty() else null
```

### Input Map

Agregar al `project.godot` la acción `cargol_command` mapeada a la tecla C:

```ini
cargol_command={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":67,"physical_scancode":0,"unicode":99,"echo":false,"script":null) ]
}
```

### Archivos

| Archivo | Acción |
|---------|--------|
| `core_v2/actors/CargolPlayerInput.gd` | Crear |
| `core_v2/actors/CargolDroneV2.tscn` | Agregar nodo `CargolPlayerInput` (opcional) |
| `project.godot` | Agregar acción `cargol_command` |

### Dependencia

La Tarea B depende de la Tarea A (`get_targets_in_range`). Jules puede
implementar ambas en secuencia dentro del mismo PR.

---

*Fin del documento.*
*Convención: `[DECIDIR]` indica que se espera input de Sebastian u Odiseo.*
