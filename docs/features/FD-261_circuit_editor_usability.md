# FD-261: Editor de circuitos usable para Dome_Intro

**Status:** Open
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-16
**Completed:** -

## Problem

El editor `addons/odyssey_circuit_editor/` (plugin "Odyssey Logic Circuit Editor") no es
utilizable para cablear los props reales de Dome_Intro. Hoy permite dibujar nodos en un
GraphEdit, pero no puede vincularlos a objetos de la escena, no persiste lo editado y no
da feedback de validación. Además el `LogicCircuitManager` inunda la consola con prints
de debug y genera los cables dos veces.

Dome_Intro usa `WallTerminal`, `SuspendedTerminalRig`, `PipeValve` (válvulas de coolant)
y `PipeSection/PipeCorner/PipeTee` — todos heredan de `InteractableBaseV2` (emiten
`activated`/`deactivated`, exponen `is_active`), así que son compatibles como nodos PROP
del circuito. El nivel todavía no tiene ningún `LogicCircuitManager` ni
`CircuitGraphResource`.

## Solution

Hacer el editor capaz de producir un `CircuitGraphResource` válido y persistible, con
nodos PROP vinculados a objetos reales de la escena, puertos tipados (entrada/salida) y
feedback de validación. Limpiar el ruido del `LogicCircuitManager` que impide trabajar.

### Gaps a cerrar (en orden de prioridad)

1. **Vincular PROP a objeto de escena (bloqueante).** "Add Prop" crea nodos con
   `scene_path` vacío y no hay forma de elegir un nodo real. Falta un scene-picker:
   - botón/selector que abra el árbol de la escena editada (`get_edited_scene_root()`) y
     guarde un `NodePath` **relativo al LogicCircuitManager** (así `_build_runtime_logic`
     lo resuelve con `get_node_or_null(path)`).
   - mostrar en el nodo del grafo el nombre resuelto (o "(sin vincular)" en rojo).

2. **Persistencia / dirty-tracking (bloqueante).** El editor muta diccionarios internos
   directo (`circuit_data.nodes[id] = ...`, `circuit_data.connections.append(...)`) sin
   pasar por `add_node`/`connect_nodes`/`remove_node`, que son los que llaman
   `emit_changed()`. Resultado: el recurso nunca se marca sucio y no se guarda.
   - Toda alta/baja/conexión debe pasar por la API del recurso, o llamar
     `emit_changed()`/marcar el recurso como modificado de forma equivalente.
   - Al salir del editor el recurso debe quedar marcado para guardar.

3. **Puertos tipados.** Hoy toda conexión fuerza puerto 0 y `set_slot` expone entrada y
   salida simétricas en cada nodo. Debe reflejarse la direccionalidad del grafo:
   - GATE: N puertos de entrada (izquierda) + 1 salida (derecha). DELAY/NOT: 1 entrada.
   - PROP: salida (emite `activated`) y **input** (recibe `set_active`).
   - `_on_connection_request` debe validar el tipo de puerto (no conectar salida→salida).

4. **Edición de propiedades.** No se puede editar `delay_time` de DELAY, `gate_type`, ni
   renombrar el `node_id` tras crearlo. Añadir un inspector mínimo al seleccionar nodo.

5. **Feedback de validación.** `CircuitGraphResource.validate()` ya existe; mostrar sus
   errores/warnings en el panel (prop sin `scene_path`, conexión a nodo inexistente, nodo
   huérfano, DELAY con delay inválido).

6. **Higiene del manager.** En `LogicCircuitManager.gd`:
   - `generate_cables()` genera cables dos veces (la primera pasada se descarta). Eliminar
     la pasada muerta.
   - Quitar los `print(...)` de debug (positions, cable generation, etc.); dejar `printerr`
     solo para errores reales.
   - Ídem los `print("[CircuitCable] ...")` de `CircuitCable.gd` (solo en debug).

## Files to Modify

- `addons/odyssey_circuit_editor/CircuitBoard.gd` (modify) — picker, dirty-tracking, puertos, inspector, validación
- `addons/odyssey_circuit_editor/CircuitBoard.tscn` (modify) — botones/paneles si hace falta
- `addons/odyssey_circuit_editor/CircuitEditorPlugin.gd` (modify) — hook del scene-picker si se resuelve acá
- `core_v2/systems/circuit/LogicCircuitManager.gd` (modify) — quitar doble generación y prints
- `core_v2/systems/circuit/CircuitCable.gd` (modify) — quitar prints
- `core_v2/systems/circuit/CircuitGraphResource.gd` (modify, opcional) — helpers de dirty si se prefiere centralizar

## Verification

1. Abrir el editor Godot, seleccionar un `LogicCircuitManager` en una escena de prueba.
2. "Add Prop" → vincularlo a un `WallTerminal` o `PipeValve` real vía picker; el nodo
   muestra el nombre resuelto.
3. Conectar PROP → GATE(AND) → PROP; guardar escena; reabrir: el grafo persiste.
4. Ejecutar validación: un prop sin vincular aparece como warning.
5. Correr el juego: al activar el prop origen, el destino recibe `set_active`.
6. Consola limpia (sin spam de cable generation); cables generados una sola vez.
7. F6 sobre el banco `core_v2/tests/TestShipSystems.tscn` sin errores.
