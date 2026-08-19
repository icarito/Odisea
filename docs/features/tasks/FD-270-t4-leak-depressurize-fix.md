# FD-270 T4 (J4): Fix H5 — `CoolantLeak` despresuriza por caudal de rama, no por una sola válvula

## Objetivo

`CoolantLeak` hoy solo pasa a `DEPRESSURIZED` cuando **su propia** `valve_path` (una sola válvula
hardcodeada) está cerrada. En una rama con dos válvulas en serie, cerrar la segunda válvula
(aguas abajo de la primera, más cerca de la fisura) no despresuriza la fisura — el flujo visual se
apaga, pero la fuga sigue pensando que tiene presión. Arreglalo para que la despresurización
dependa del caudal real del tramo, no de una sola válvula fija.

## Contexto del sistema

Godot 3.6 / GDScript 1.x (`export()` con paréntesis, `yield` nunca `await`). Todo en `core_v2/`.

Archivo a editar: `core_v2/systems/cryo/CoolantLeak.gd` (leelo completo antes de tocar nada, ya
está en el repo). Es una máquina de estados: `HEALTHY -> WARNING -> LEAKING -> SEALED /
DEPRESSURIZED`.

## El bug exacto

```gdscript
export(NodePath) var valve_path: NodePath
...
func _ready() -> void:
    if valve_path != null and not valve_path.is_empty():
        var valve = get_node_or_null(valve_path)
        if valve and valve.has_signal("valve_state_changed"):
            valve.connect("valve_state_changed", self, "_on_valve_state_changed")
    ...

func _on_valve_state_changed(is_open: bool) -> void:
    if is_open:
        trigger_leak()
    else:
        depressurize()
```

`valve_path` conecta a **una** válvula. En el laboratorio actual, cada rama tiene dos válvulas en
serie antes de la fisura (`ValveWest_1` → `ValveWest_2` → `LeakWest`). El escenario provisto ya
apunta `LeakWest.valve_path` a `ValveWest_1` (será recableado a `ValveWest_2`, la inmediatamente
aguas arriba, en una tarea de escena aparte — no es tu tarea). Pero **aunque el NodePath apunte a
la válvula correcta, seguís teniendo el problema de fondo**: la fisura solo escucha una válvula,
y en una topología con más tramos aguas arriba (una T, una rama más larga), cualquier válvula
más lejana que corte el caudal no dispara `depressurize()`.

## Dependencia: contrato de `CoolantFlowAdapter` v2 (en curso, ver abajo)

Hay otra tarea en paralelo (T2/J2) reescribiendo `core_v2/systems/cryo/CoolantFlowAdapter.gd`.
**No la esperes ni la edites** — escribí tu código contra el contrato que sigue:

```gdscript
func is_pressurized_at(node: Node) -> bool
```

Ya devuelve si el tramo de tubería donde está `node` (una fisura) tiene caudal `> 0.0`. El
adapter también va a emitir (o ya emite, si heredás la convención del resto del repo) un
recálculo disparado por señales de válvula/fuga — pero **no dependas de una señal nueva que no
esté ya especificada acá**; en vez de eso, agregá un `NodePath` nuevo a `CoolantLeak` para
resolver el adapter y **preguntarle activamente** cuando haga falta reevaluar.

## Cambio a implementar

1. **Agregar** `export(NodePath) var flow_adapter_path: NodePath` a `CoolantLeak.gd`, resuelto en
   `_ready()` igual que `valve_path` hoy (a una var interna `_flow_adapter`).

2. **Conservar `valve_path`** tal cual está (el export, la conexión a `valve_state_changed`, y
   `_on_valve_state_changed`) — sigue siendo el disparador inmediato para la válvula
   *directamente* adyacente (útil para la transición instantánea al cerrar/abrir esa válvula
   puntual). No lo borres ni cambies su comportamiento actual.

3. **Agregar una verificación adicional** de presión real usando el adapter, en los puntos donde
   la máquina de estados evalúa si debe estar despresurizada. Concretamente: en
   `_on_valve_state_changed`, cuando `is_open == true` (la válvula propia se abrió), **antes** de
   llamar `trigger_leak()`, si hay `_flow_adapter` conectado, chequeá
   `_flow_adapter.is_pressurized_at(self)` — si devuelve `false` (otra válvula más aguas arriba
   sigue cerrada y el tramo sigue seco), quedate en `DEPRESSURIZED` en vez de disparar
   `trigger_leak()`. Es decir: la válvula propia abrirse ya no es condición suficiente, tiene que
   haber caudal real.

   ```gdscript
   func _on_valve_state_changed(is_open: bool) -> void:
       if is_open:
           if _flow_adapter != null and _flow_adapter.has_method("is_pressurized_at"):
               if not bool(_flow_adapter.call("is_pressurized_at", self)):
                   return  # otra válvula aguas arriba sigue cortando el caudal
           trigger_leak()
       else:
           depressurize()
   ```

4. **`trigger_leak()`** ya tiene una comprobación temprana de `valve_path` cerrada al inicio (ver
   el archivo actual) — dejala como está, es la verificación local rápida. La verificación nueva
   del punto 3 es la que cubre válvulas *no* directamente conectadas a esta fisura.

No hace falta que `CoolantLeak` pase a escuchar una señal del adapter (`flow_changed` o similar) —
alcanza con la consulta activa (`is_pressurized_at`) en el momento de la transición de válvula.

## Archivos permitidos

- `core_v2/systems/cryo/CoolantLeak.gd`
- Un test GdUnit3 nuevo en `core_v2/tests/` (ver criterio de aceptación abajo)

## Archivos prohibidos

- `core_v2/systems/cryo/CoolantFlowAdapter.gd` (otra tarea la está escribiendo en paralelo)
- `core_v2/systems/pipe/PipeNetworkResource.gd`
- `core_v2/systems/cryo/LeakPatchPoint.gd`
- Cualquier `.tscn`, `project.godot`

## Criterio de aceptación

Test GdUnit3 que cubra: con la válvula propia (`valve_path`) abierta pero un adapter mock que
responde `is_pressurized_at() -> false` (simulando otra válvula más aguas arriba cerrada), la
fisura debe permanecer en `DEPRESSURIZED` y `get_leak_intensity()` no debe empezar a subir. Con el
mismo adapter mock devolviendo `true`, la fisura sí debe poder pasar a `WARNING`/`LEAKING` vía
`trigger_leak()`.

Para el mock, un `Node` con `set_script()` de un script mínimo que expone
`is_pressurized_at(node) -> bool` alcanza. Mirá `core_v2/tests/test_pipe_network_resource.gd` (ya
en el repo) para el estilo general: `extends GdUnitTestSuite`, `auto_free()`, `assert_*`.

Correr `./runtest.sh -a core_v2/tests/<tu_test>.gd` y que pase. Verificá también que los tests
existentes de `CoolantLeak` (buscá `test_*leak*` o `test_*coolant*` en `core_v2/tests/`) sigan
pasando después de tu cambio — no deberían romperse porque `flow_adapter_path` es opcional
(comportamiento sin conectar = igual que hoy).

## Qué NO hacer

- No edites `CoolantFlowAdapter.gd` — otra tarea lo está escribiendo, tocarlo genera conflicto de
  merge.
- No cambies el resto de la máquina de estados (`WARNING`, `LEAKING`, `SEALED`, `seal()`,
  `set_active()`, `_apply_room_deltas()`) — el cambio es acotado a la despresurización por
  válvula.
- No borres `valve_path` ni su conexión existente.
- No toques ninguna escena ni recablees `LeakWest.valve_path` — eso es tarea de escena aparte.

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
