# FD-270 T2 (J2): `CoolantFlowAdapter` v2 — barrido por topología

## Objetivo

Reescribir `core_v2/systems/cryo/CoolantFlowAdapter.gd` para que calcule el caudal **por tramo**,
en vez de un único booleano para toda la corrida. Consume el `PipeNetworkResource` ya existente
en `core_v2/systems/pipe/PipeNetworkResource.gd` (leelo primero, es el contrato de datos).

## Contexto del sistema

Godot 3.6 / GDScript 1.x (`export()` con paréntesis, `yield` nunca `await`). Todo en `core_v2/`.

El puzle: refrigerante corre desde un tanque, atraviesa válvulas, y una fisura en el camino
absorbe parte del caudal. Hoy `CoolantFlowAdapter` calcula un solo booleano
(`all_valves_open and tank_level > 0`) y lo aplica **a todos los tramos por igual** — cerrar
cualquier válvula apaga el caño entero, incluido el tramo entre el tanque y esa válvula. El
objetivo de este FD es que el jugador vea la corriente "morir" exactamente en el tramo con la
avería, y que los tramos aguas arriba de una válvula cerrada sigan corriendo normal.

`PipeNetworkResource.branches[branch_id]` da, en orden, la lista de tramos (`segments`) de una
rama, cada uno con su `pipe_run` (nodo `PipeCoolantRun`, ya existe en el repo —
`core_v2/props/pipe/PipeCoolantRun.gd`, no lo edites), su `valve` opcional (en la entrada del
tramo) y su `leak` opcional (en la entrada del tramo).

`PipeCoolantRun` ya expone `set_flow_speed(v: float)` y `set_flow_intensity(v: float)` — no hace
falta tocar ese archivo ni el shader, ya soportan velocidad/intensidad independientes por
instancia.

## El algoritmo (ya especificado, no rediseñar)

Un barrido O(n) en orden, sin solver, sin iterar a convergencia:

```gdscript
func compute_flow() -> void:
    var carrying := 1.0 if _tank.tank_level > 0.0 else 0.0
    for i in range(_segments.size()):
        var seg = _segments[i]
        if seg.valve != null and not seg.valve.is_open():
            carrying = 0.0
        var f := carrying
        if seg.is_downstream_of_leak:
            f = carrying * (1.0 - _leak.get_leak_intensity())
        seg.flow = f
```

Adaptalo a la forma real de `PipeNetworkResource` (resolver los `NodePath` de cada segmento a
nodos reales, no a la pseudo-clase `seg` de arriba). El punto clave: una vez que `carrying` cae a
0 (válvula cerrada) o se multiplica por `(1 - intensidad)` (fisura), ese valor se propaga a todos
los tramos siguientes de la rama — no hay "recuperación" aguas abajo.

## Contrato del adapter v2

- **Exports nuevos:** `export(Resource) var network` (un `PipeNetworkResource`) y
  `export(String) var branch_id` (qué rama de `network.branches` gobierna este adapter). Un
  adapter por rama — el laboratorio va a tener dos instancias, una para `"west"` y otra para
  `"east"`.
- **Eliminar:** `circuit_manager_path`, `_manager`, y toda referencia a
  `LogicCircuitManager`/OCLS — el comentario de cabecera actual dice "Reads OCLS circuit state"
  pero el código nunca lo hizo; hay que borrar el código muerto y el comentario falso, no
  conservar nada de eso. También eliminar los exports planos `valves`, `leaks`, `pipe_runs` (los
  reemplaza `network`/`branch_id`).
- **`_resolve_references()` una sola vez:** hoy corre en cada `_physics_process` (60Hz) haciendo
  `get_node_or_null` por cada válvula/fuga/corrida. Debe correr solo en `_ready()`. Guardá los
  nodos resueltos (válvulas, fugas, pipe runs, tanque) en arrays/vars internas para no re-resolver
  paths en cada recálculo.
- **Recálculo por señal, no por physics tick:** conectate a `valve_state_changed` de cada válvula
  de la rama, a `state_changed` de cada fuga de la rama, y a lo que dispare el drenaje del tanque
  (mirá cómo `_tank.set_tank_level()` se usa hoy en el adapter actual — el drenaje sigue
  ocurriendo con `delta`, así que probablemente conviene mantener un `_physics_process` liviano
  solo para el drenaje del tanque y el drenaje dispara el recálculo, pero el recálculo en sí
  **no** debe iterar válvulas/fugas por polling cada frame; usá señales para eso). La suavidad
  visual no se pierde: la rampa de velocidad ya vive en `PipeCoolantRun._current_speed`
  (`_approach()`), así que el adapter solo necesita escribir el *objetivo* cuando cambia, no
  interpolar él mismo.
- **API pública nueva:**
  - `get_segment_flow(index: int) -> float` — caudal normalizado `0..1` del tramo `index` de la
    rama que gobierna este adapter.
  - `is_pressurized_at(node: Node) -> bool` — dado un nodo (una fisura, típicamente), encuentra en
    qué tramo de la rama está esa fisura (por su NodePath `leak` en `PipeNetworkResource`) y
    devuelve si el caudal de ESE tramo es `> 0.0`. Esta función va a reemplazar al manómetro como
    autoridad de "¿se puede parchear en firme?" en una tarea posterior — dejala lista pero no
    edites `LeakPatchPoint.gd` en esta tarea, es un archivo prohibido acá.
  - **Conservar** `is_flow_active() -> bool` con la misma firma que hoy, pero reimplementada como
    `get_segment_flow(0) > 0.0` (el primer tramo de la rama, el que sale del tanque) —
    `CoolantLab.gd` la sigue llamando y no se edita en esta tarea.
- **Velocidad/intensidad por tramo, no global:** en vez de escribir el mismo `target_speed`/
  `target_intensity` a todos los `pipe_runs` como hoy, cada `PipeCoolantRun` de la rama recibe
  `set_flow_speed(normal_flow_speed * flow[i])` y `set_flow_intensity(normal_flow_intensity *
  flow[i])`, donde `flow[i]` es el caudal normalizado `0..1` de ESE tramo específico (no el
  booleano global de antes).
- **Drenaje del tanque:** conservar la lógica de que una fuga activa drena el tanque con
  `drain_rate * intensidad * delta` — igual que hoy, pero ahora por fuga individual de la rama, no
  sumando "total_leak_intensity" de una lista plana desconectada de la topología.

## Determinismo (§8 del FD, importante)

- El adapter sigue en el grupo `replay_sync`.
- `get_snapshot()` debe guardar el **Array de caudales por tramo** (`Array[float]`, uno por
  segmento de la rama), no los tres escalares actuales (`flow`/`speed`/`intensity`).
- `restore_snapshot()` reaplica esos caudales a los `pipe_runs` correspondientes.
- **No** guardar `_phase` de ningún `PipeCoolantRun` — es cosmético, no entra en el estado lógico
  determinista (ya es así hoy, no lo cambies).
- El barrido debe seguir siendo un recorrido de `Array` en orden fijo (el orden de `segments` en
  `PipeNetworkResource`), sin iterar `Dictionary` para el cálculo en sí, para que el resultado sea
  reproducible byte a byte entre corridas del replay.

## Archivos permitidos

- `core_v2/systems/cryo/CoolantFlowAdapter.gd`
- Un test GdUnit3 nuevo en `core_v2/tests/` para los dos casos de aceptación de abajo (mirá
  `core_v2/tests/test_pipe_network_resource.gd`, que ya está en el repo, para el estilo:
  `extends GdUnitTestSuite`, `auto_free()`, `assert_*`)

## Archivos prohibidos

- `core_v2/systems/pipe/PipeNetworkResource.gd` (ya existe, no lo edites — si te falta algo del
  contrato, usalo tal cual está, no lo extiendas)
- `core_v2/props/pipe/PipeCoolantRun.gd` (ya expone lo que necesitás)
- `core_v2/systems/cryo/CoolantLeak.gd`
- `core_v2/systems/cryo/LeakPatchPoint.gd`
- `core_v2/scenes/CoolantLab.gd` y cualquier `.tscn`
- `project.godot`

## Criterio de aceptación

Dos tests GdUnit3 (nombres sugeridos, podés ajustar):

- **`test_flow_prefix_scan`**: armar una rama de 3-4 tramos con nodos de prueba (`Node.new()`,
  ver el estilo de `test_pipe_network_resource.gd`), simular una válvula cerrada en el tramo `i`
  (un nodo mock con método `is_open()` devolviendo `false`, o usá `PipeValve` real si es más
  simple instanciarlo en test), y verificar que `get_segment_flow(j) > 0` para `j < i` y
  `get_segment_flow(j) == 0` para `j >= i`.
- **`test_leak_kills_downstream`**: con una fuga de intensidad `1.0` en el tramo `i`, verificar
  `get_segment_flow(i) == 0` (o cerca de 0) y que el tramo anterior (`i-1`, si existe) mantiene
  caudal `> 0`.

Correr `./runtest.sh -a core_v2/tests/<tu_test>.gd` y que pasen.

## Qué NO hacer

- No implementes `is_pressurized_at` conectándolo a `LeakPatchPoint` — eso es la tarea siguiente
  (J3), archivo prohibido acá.
- No arregles H5 (el `valve_path` de `CoolantLeak` apunta a la válvula equivocada) — es
  `CoolantLeak.gd`, archivo prohibido acá, tarea aparte (J4).
- No toques el shader ni `PipeCoolant.tres` — ya soportan lo que hace falta.
- No agregues un solver genérico ni resolución a convergencia — el barrido de una pasada es
  suficiente porque el grafo es un árbol sin ciclos, por contrato.
- No instancies `PipeNetworkResource` en ninguna escena — eso lo hacemos nosotros a mano después.

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
