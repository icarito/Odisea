# FD-255 J1 — Determinismo del LogicCircuitManager

## Objetivo

`LogicCircuitManager` es el pegamento de los cuatro sistemas de la nave (FD-255): las válvulas,
levers y diales de cada sistema se conectan a puertas y efectos a través de su grafo de
circuito. Hoy **no cumple el contrato de replay determinista del proyecto**, así que cualquier
puerta que dependa del circuito diverge al reproducir un replay.

Hay que hacerlo replay-safe: agregarlo al grupo `replay_sync` e implementar
`get_snapshot()` / `restore_snapshot()` completos, con un test que lo demuestre.

## Contexto

- Archivo: `core_v2/systems/circuit/LogicCircuitManager.gd` (586 líneas).
- Documentación del sistema: `docs/interaction/CIRCUIT_SYSTEM.md` y
  `core_v2/systems/circuit/README.md`.
- El contrato de replay está en `AGENTS.md` §5.3. Resumen: todo agente sincronizado pertenece al
  grupo `replay_sync`, implementa `restore_snapshot(data: Dictionary)`, y corre su lógica en
  `_physics_process`. `LogicCircuitManager` **ya** corre en `_physics_process` (bien); lo que
  falta es el grupo y el par snapshot/restore.
- Ejemplos del patrón ya implementado en este repo, para copiar estilo y forma del diccionario:
  - `core_v2/systems/gas/GasParticleManager.gd` → `get_snapshot()` / `restore_snapshot()`
  - `core_v2/props/pipe/PipeValve.gd` → versión mínima sobre `InteractableBaseV2`
  - `core_v2/props/emitters/FrostEmitter.gd`

## Estado actual (verificado)

- `_ready()` agrega el nodo al grupo `olcs_manager`, **no** a `replay_sync`.
- No existen `get_snapshot()` ni `restore_snapshot()`. Sí existe `anna_get_snapshot(max_entries)`,
  que es **solo para debug/telemetría**: no lo reutilice como contrato, no lo rompa.
- Estado de runtime a preservar:
  - `_runtime_nodes`: `Dictionary` de `node_id` → `{ type, ref, gate_type, delay_time, state, inputs }`.
  - `_input_queue`: `Array` de `{ target, input, value }`.
  - `_output_queue`: `Array` de `{ source, value, delay }` — el `delay` decrece por tick y es lo
    que hace funcionar las compuertas `DELAY`.
  - `_cables`: `Dictionary` de hash → `CircuitCable`. Los cables se regeneran; ver más abajo.

## Qué implementar

1. **Grupo.** En `_ready()`, `add_to_group("replay_sync")` además del grupo actual.

2. **`get_snapshot() -> Dictionary`.** Debe capturar el estado lógico completo:
   - Por cada entrada de `_runtime_nodes`: `state` y una copia de `inputs`. **No serializar
     `ref`**: es un `Node` vivo, se resuelve por `node_id` contra `circuit_data` al restaurar.
     `type`, `gate_type` y `delay_time` salen de `circuit_data`, así que no hace falta guardarlos
     (guárdelos solo si simplifica la restauración).
   - Copias de `_input_queue` y `_output_queue`, incluyendo el `delay` restante de cada entrada
     pendiente. Un `DELAY` a mitad de camino tiene que seguir a mitad de camino tras restaurar.
   - Use estructuras serializables (Dictionary / Array / tipos primitivos). Duplique los arrays
     y diccionarios anidados (`.duplicate(true)` donde corresponda): no deje referencias vivas
     al estado interno dentro del snapshot.

3. **`restore_snapshot(data: Dictionary) -> void`.** Debe dejar el circuito exactamente como
   estaba:
   - Restaurar `state` e `inputs` de cada nodo que siga existiendo en `_runtime_nodes`. Ignorar
     con tolerancia los ids que ya no existen (el grafo pudo cambiar): no crashear.
   - Restaurar las dos colas con sus delays pendientes.
   - **Re-aplicar el estado a los props**: por cada nodo `PROP` con `ref` válido y método
     `set_active`, llamarlo con el `state` restaurado, para que la puerta/válvula del mundo
     coincida con el circuito. Usar `is_instance_valid(ref)` antes de tocarlo.
   - Los `CircuitCable` son visuales: basta con reflejar el estado (`set_active`) en los que
     existan. No regenerar cables dentro de `restore_snapshot`.

4. **Test nuevo:** `core_v2/tests/test_circuit_determinism.gd`, GdUnit3, siguiendo el estilo de
   `core_v2/tests/test_circuit_graph_resource.gd` (mismo directorio, ya existe, úselo de molde).
   Debe cubrir, sin depender de una escena de nivel:
   - Armar por código un `CircuitGraphResource` con al menos: dos props de entrada, una compuerta
     `AND` y una compuerta `DELAY`, y un prop de salida.
   - Correr N ticks llamando a `step(delta)` con un delta fijo (`1.0 / 60.0`).
   - Tomar `get_snapshot()`, seguir corriendo, restaurar, volver a correr los mismos ticks, y
     verificar que el estado final es idéntico (estados de nodos y estado del prop de salida).
   - Un caso específico para `DELAY`: snapshot **con un cambio pendiente en la cola**, restaurar,
     y comprobar que el cambio se aplica en el mismo tick que sin restaurar.

## Archivos

**Permitidos** (solo estos):
- `core_v2/systems/circuit/LogicCircuitManager.gd`
- `core_v2/tests/test_circuit_determinism.gd` (nuevo)

**Prohibidos:** cualquier `.tscn`, `project.godot`, `core_v2/systems/gas/**`,
`core_v2/props/emitters/**`, `core_v2/systems/cryo/**` (hay otras tareas trabajando ahí en
paralelo), y el resto de `core_v2/systems/circuit/` salvo el archivo listado.

## Convenciones del proyecto

- **Godot 3.6, GDScript 1.x.** `yield()`, no `await`. `onready var`, no `@onready`.
  `connect("signal", self, "_metodo")` con strings.
- Tipado estático en código nuevo: `func f(v: float) -> void:`, `var x: int = 0`.
- Cambios chicos y enfocados. No reescribir el archivo ni reordenar lo que ya funciona.
- **Ojo con la indentación:** el archivo mezcla tabs y espacios según el bloque. Respete la
  indentación del bloque que esté editando; no reindente el archivo entero.
- No introducir `randf()`, `randi()` ni `Engine.get_frames_drawn()` en la lógica.
- No tocar `anna_get_snapshot()`, `anna_inject_input()`, `anna_set_output()` ni
  `anna_rebuild_cables()`: son la API de debug y hay herramientas que la usan.

## Aceptación

```bash
./runtest.sh -a ./core_v2/tests/test_circuit_determinism.gd    # el test nuevo pasa
./runtest.sh -a ./core_v2/tests/test_circuit_graph_resource.gd # no se rompió lo existente
./runtest.sh -a ./core_v2/tests/test_circuit_terminal_bridge.gd
```

El output de los tests queda en `./reports/gdunit_runner.log`.

## Qué NO hacer

- No agregar una capa de "sistema de nave" ni una clase base nueva: esta tarea es solo
  determinismo del manager existente.
- No cambiar la semántica de las compuertas ni el orden de propagación: el circuito ya funciona,
  solo tiene que poder guardarse y restaurarse.
- No tocar la generación de cables (`generate_cables`, `_spawn_cable`, `_generate_catenary`).
- No crear escenas de ejemplo ni props nuevos.
