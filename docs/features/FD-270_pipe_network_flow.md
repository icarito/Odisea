# FD-270: Red de tuberías con caudal por tramo

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-18
**Parent:** FD-255 (Maestro) / FD-256 (Criocoolant) / FD-264 (grafo OCLS) / FD-265 (laboratorio) / FD-266 (semántica del puzle)
**Alcance de implementación:** `CoolantLab.tscn` primero. Migración a `Dome_Intro.tscn` en §7.

## Problem

FD-266 dejó el ciclo *cerrar → parchear → reabrir* correcto a nivel de máquina de estados. Lo que
falta es que **el jugador pueda ver dónde está el problema y qué válvula lo alimenta**, sin texto y
sin instrumentos.

La decisión de diseño que motiva este FD: **el shader de flujo es el canal de información del
puzle**. El refrigerante corre desde el tanque, atraviesa el recorrido, y *muere en la fisura*. El
tramo aguas abajo queda quieto. Ese punto donde la corriente se apaga es la avería, y no hace falta
nombrarla. De ahí se sigue el trabajo del jugador: seguir el caño hacia atrás con el cuerpo hasta la
válvula que lo alimenta.

**El código actual no puede producir esa imagen.** Los hallazgos, con evidencia:

### H1 — `CoolantFlowAdapter` no tiene topología

```gdscript
export(Array, NodePath) var valves: Array = []
export(Array, NodePath) var pipe_runs: Array = []
```

Listas planas. Ningún dato dice qué válvula está aguas arriba de qué tramo. El cálculo colapsa todo
en un booleano y lo escribe a todas las corridas por igual:

```gdscript
var flow_active := (all_valves_open) and (tank_level > 0.0)
...
for pr_path in pipe_runs:
    pr.call("set_flow_speed", target_speed)
```

Consecuencia: **cerrar cualquier válvula apaga el caño entero**, incluido el tramo entre el tanque y
esa válvula. No se puede ver dónde se corta el caudal porque se corta en todos lados a la vez.

### H2 — La fuga atenúa, no interrumpe

```gdscript
if active_leak_factor > 0.0 and flow_active:
    target_intensity = max(0.1, target_intensity * (1.0 - active_leak_factor * 0.4))
```

La corrida entera baja un 40 %. No existe un punto donde la corriente muere. Ese punto era el canal
de información completo.

### H3 — La topología ya está authored, y nadie la lee

El `CircuitGraphResource` embebido en `CoolantLab.tscn` contiene exactamente la cadena ordenada:

```
TankWest → ValveWest_1 → ValveWest_2 → LeakWest
TankEast → ValveEast_1 → ValveEast_2 → LeakEast
```

Mientras tanto `CoolantFlowAdapter` exporta `circuit_manager_path`, resuelve `_manager` en
`_resolve_references()` y **nunca lo lee**. El comentario del archivo afirma *"Reads OCLS circuit
state"*. No lo hace.

### H4 — En `CoolantLab` hay una sola corrida por rama, y no cubre la cadena

| Nodo | Posición (rama oeste) |
|---|---|
| `TankWest` | `(-8, 0, -4)` |
| `ValveWest_1` | `(-5, 1, -4)` |
| `ValveWest_2` | `(-2, 1, -4)` |
| `LeakWest` | `(1, 1, -4)` |
| `PipeRunWest` | `(-3.5, 1, -4)` — **un solo cilindro** |

No hay caño entre el tanque y la válvula 1, ni entre la válvula 2 y la fisura, ni **nada aguas abajo
de la fisura**. El tramo que más trabajo narrativo hace —el que debe quedarse quieto— no existe como
objeto. La rama este es espejo: tanque `(8,0,2)`, V1 `(5,1,2)`, V2 `(2,1,2)`, fuga `(-1,1,2)`,
corrida única en `(3.5,1,2)`.

### H5 — `CoolantLeak` observa una sola válvula

`CoolantLeak` tiene un `valve_path` escalar, y en la escena apunta a `ValveWest_1`. El adapter, en
cambio, exige que **todas** las válvulas estén abiertas.

Resultado: cerrar `ValveWest_2` apaga el flujo visual, pero la fuga nunca pasa a `DEPRESSURIZED`. El
jugador ve el caño quieto, dispara gloo, y le sale un parche **provisorio**. Es la peor clase de
error: el feedback visual dice una cosa y la regla dice otra.

### H6 — El manómetro es hoy la autoridad del parche

```gdscript
var pressure := 0.0
if _manometer != null and _manometer.has_method("get_pressure"):
    pressure = float(_manometer.get_pressure())
elif _leak != null and _leak.has_method("get_leak_intensity"):
    ...
var applies_firmly := (pressure <= firm_patch_pressure_threshold)
```

`LeakPatchPoint` decide firme vs. provisorio leyendo el manómetro. Como el manómetro se retira del
puzle (§10, [DECIDIR] resuelto), hay que mover esa autoridad **antes** de sacarlo, o el nivel cae al
fallback silenciosamente.

## Solution

### §1 — Sin solver. El caudal es un barrido ordenado.

La topología es un **árbol dirigido** desde el tanque: tanque → válvulas → fisura → sumidero. No hay
ciclos, ni bifurcaciones que repartan caudal por proporción, ni flujo bidireccional.

El caudal de cada tramo se calcula con una pasada en orden:

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

O(n), una pasada, sin iterar a convergencia.

**Regla que mantiene esto válido: el grafo de tuberías no puede tener ciclos.** Con esa restricción,
agregar una T más adelante sigue sin necesitar solver — un árbol se recorre con un DFS, también una
pasada. Un solver haría falta únicamente con ciclos, y los ciclos se prohíben por contrato.

### §2 — ¿OCLS sirve acá?

**Para el caudal, no.** OCLS propaga booleanos por eventos, con compuertas y delays, en cola con
`MAX_LOGIC_STEPS`. No tiene noción de orden a lo largo de un camino físico, ni de magnitud flotante,
ni de "aguas arriba". El caudal necesita las tres.

**Para la victoria, sí, y es donde ya está bien usado.** *Ambas fisuras selladas en firme AND ambas
válvulas abiertas → `HeavyBlastDoor`* es booleano y por eventos: es exactamente el trabajo de OCLS y
de FD-259.

**Sobre reutilizar el grafo OCLS como fuente de topología** (H3 muestra que la cadena ya está ahí):
tentador, pero acopla dos semánticas en la misma arista. Una arista OCLS significa *"la señal se
propaga"*; una arista de tubería significa *"por este tramo físico corre fluido, y ese tramo tiene un
`PipeCoolantRun` con dirección"*. La segunda necesita campos que la primera no tiene. FD-267 ya
muestra el costo de que ese grafo haga doble tarea (los cables planos). Se propone recurso separado
— ver [DECIDIR] D1.

### §3 — `PipeNetworkResource`

Recurso nuevo en `core_v2/systems/pipe/PipeNetworkResource.gd`. Guarda la topología ordenada, una
entrada por rama.

```gdscript
extends Resource
class_name PipeNetworkResource

# branches: Dictionary { branch_id (String) -> BranchData }
# BranchData: {
#   "tank": NodePath,
#   "segments": Array of SegmentData   # EN ORDEN, del tanque al sumidero
# }
# SegmentData: {
#   "pipe_run": NodePath,   # el PipeCoolantRun de este tramo
#   "valve": NodePath,      # opcional: válvula EN LA ENTRADA de este tramo
#   "leak": NodePath,       # opcional: fisura EN LA ENTRADA de este tramo
#   "flow_dir": Vector3     # dirección de este tramo, en mundo
# }
export(Dictionary) var branches := {}
```

Semántica de `valve` y `leak`: van **en la entrada** del tramo. Una válvula cerrada en el tramo `i`
pone en cero `i` y todo lo que sigue; el tramo `i-1` conserva su caudal. Una fisura en el tramo `i`
multiplica por `(1 - intensidad)` desde `i` en adelante.

`validate()` debe rechazar: un `NodePath` que no resuelve, una rama sin tanque, una rama con cero
tramos, y **cualquier `pipe_run` que aparezca en más de un tramo** (sería un caño con dos caudales).

### §4 — Contrato de `CoolantFlowAdapter` v2

Cambios sobre el archivo actual:

- Se reemplazan `valves` y `pipe_runs` por `export(Resource) var network` y `export(String) var branch_id`.
- Se **elimina** `circuit_manager_path` y `_manager` (H3: código muerto).
- `_resolve_references()` corre **una sola vez** en `_ready()`, no cada frame de física. Hoy hace
  `get_node_or_null` sobre cada válvula, cada fuga y cada corrida a 60 Hz para un estado que solo
  cambia cuando se toca una válvula.
- El recálculo pasa a ser **por señal**: `valve_state_changed`, `state_changed` de la fuga, y el
  drenaje del tanque. La suavidad no se pierde: la rampa vive en `PipeCoolantRun._current_speed`.
- Nueva API pública: `get_segment_flow(index) -> float` y `is_pressurized_at(node) -> bool`.

`is_pressurized_at()` es la que reemplaza al manómetro como autoridad del parche (H6): pregunta el
caudal del tramo donde está la fisura. Con eso, **lo que el jugador ve es lo que la regla evalúa**.

### §5 — Reglas de autoría de escena

**R1. Una corrida no puede cruzar una válvula ni una fisura.** Es la restricción que hace posible
mostrar caudales distintos a cada lado. Es de escena, no de código, y es barata.

**R2. Cada corrida es un tramo recto.** `PipeCoolantRun.flow_dir` es un `Vector3` único en
coordenadas de mundo; si la corrida dobla 90°, la dirección queda mal para la mitad. Los codos van
como nodos propios sin material de flujo, o como corridas separadas.

**R3. Toda rama tiene un tramo aguas abajo de la fisura.** Es el que se queda quieto. Sin él no hay
lectura (H4).

**R4. `CoolantLeak.valve_path` debe apuntar a la válvula *inmediatamente* aguas arriba**, y la
condición de despresurización debe venir del adapter, no de esa única válvula (H5).

### §6 — Implementación en `CoolantLab`

El laboratorio es el banco de pruebas: dos ramas espejadas, todas las piezas instanciadas, sin
geometría de domo que estorbe. Se implementa acá primero y completo.

**T1 — Geometría por tramos.** Partir `PipeRunWest` en cuatro corridas rectas sobre `z = -4`, `y = 1`:

| Tramo | De → a | Válvula en la entrada | Nota |
|---|---|---|---|
| `S0` | `x=-8` → `x=-5` | — | tanque a V1 |
| `S1` | `x=-5` → `x=-2` | `ValveWest_1` | |
| `S2` | `x=-2` → `x=1` | `ValveWest_2` | |
| `S3` | `x=1` → `x=4` | fisura `LeakWest` | **el que se queda quieto** |

Rama este espejada sobre `z = 2`: `x=8 → 5 → 2 → -1 → -4`.

**T2 — Sumidero.** `S3` termina en un nodo `CryoLoopSink` (`x=4` / `x=-4`). No necesita lógica: es
el ancla que le da a la corrida un final legible.

**T3 — `PipeNetworkResource`** con las dos ramas, embebido como `SubResource` en `CoolantLab.tscn`
igual que hoy está el `CircuitGraphResource`.

**T4 — `CoolantFlowAdapter` v2** según §4, un adapter por rama, apuntando al recurso con su
`branch_id`.

**T5 — Autoridad del parche.** `LeakPatchPoint` deja de leer el manómetro y pasa a preguntar
`flow_adapter.is_pressurized_at(leak)`. Se conserva `firm_patch_pressure_threshold` como umbral
sobre el caudal normalizado `0..1` — ojo, hoy convive con un `> 2.0` en `CoolantLab._update_status()`
que sugiere otra escala; unificar a `0..1`.

**T6 — Corregir H5.** `LeakWest.valve_path` → `ValveWest_2` (la inmediatamente aguas arriba), y la
transición a `DEPRESSURIZED` gobernada por el caudal del tramo.

**T7 — Retirar el manómetro del puzle.** Ver §10 D2.

**Criterio de aceptación, jugable y verificable a ojo:** con la fuga activa, se ve la corriente
correr desde el tanque y **detenerse en la fisura**, con `S3` quieto. Al cerrar `ValveWest_2`, se
apagan `S2` y `S3` y **`S0` y `S1` siguen corriendo**. Al cerrar `ValveWest_1`, se apaga todo salvo
`S0`.

### §7 — Migración a `Dome_Intro`

Nada de lo anterior toca `Dome_Intro.tscn`. Cuando el laboratorio pase el criterio de aceptación:

1. `Dome_Intro` hoy no tiene `Room3D`, ni `LogicCircuitManager`, ni `LeakPatchPoint`: sus válvulas y
   tuberías son el decorado horneado de FD-261. Ese cableado es prerrequisito y no es parte de este FD.
2. Los tres grupos existentes (`CryoLoopWest`, `CryoLoopEast`, `TowerCoolantRiser`) deben partirse
   según R1 y R2. `tools/bake_pipe_network.gd` es el lugar donde imponer la regla al hornear.
3. El trazado del domo debe **cruzarse a propósito**: la válvula que el jugador tiene al lado no
   debería ser la de la fuga que acaba de ver. Ese es el puzle. El layout espacial es dominio del
   autor y no se especifica acá.
4. El sumidero de cada rama en el domo es el bucle de criogenia real, no un nodo vacío.

### §8 — Determinismo

`CoolantFlowAdapter` sigue en `replay_sync`. El barrido de §1 es determinista por construcción:
recorrido de un `Array` en orden fijo, sin diccionarios iterados, sin dependencia de orden de nodos
en el árbol de escena.

`get_snapshot()` debe pasar a guardar el `Array` de caudales por tramo, no los tres escalares
actuales. `restore_snapshot()` reaplica a las corridas.

**No** se debe guardar `_phase` de `PipeCoolantRun`: la fase es puramente cosmética y la determinismo
del `core_v2` exige que la capa visual no entre en el estado lógico.

### §9 — Tests (GdUnit3)

- `test_flow_prefix_scan`: cerrar la válvula del tramo `i` deja `flow[j] > 0` para `j < i` y
  `flow[j] == 0` para `j >= i`.
- `test_leak_kills_downstream`: con intensidad 1.0, `flow[S3] == 0` y `flow[S2] > 0`.
- `test_no_cycles`: `PipeNetworkResource.validate()` rechaza un `pipe_run` repetido en dos tramos.
- `test_firm_patch_requires_zero_flow`: parchear con `flow > threshold` da provisorio; con `flow == 0`
  da firme.
- `test_snapshot_roundtrip`: guardar y restaurar reproduce los mismos caudales por tramo.

### §10 — `[DECIDIR]`

- **D1 — ¿Recurso separado o extender `CircuitGraphResource`?** **Decidido: recurso separado**
  (`PipeNetworkResource`, §3). El argumento en contra —duplicar topología ya authored en OCLS— se
  acepta como costo menor frente a acoplar dos semánticas distintas en la misma arista (§2, FD-267
  como precedente del riesgo).
- **D2 — Destino del `PipeManometer`.** Decidido en sesión: sale del puzle. Falta decidir si se
  borra el prop, se reubica como lectura del tanque, o queda como adorno sin función.
  `[DECIDIR]`
- **D3 — ¿La velocidad del shader codifica caudal, o solo encendido/apagado?** **Decidido: codifica
  caudal parcial.** `flow_speed` y `flow_intensity` escalan con el caudal normalizado del tramo
  (`0..1`); consistente con cómo ya funciona `set_flow_intensity()` en `PipeCoolantRun`. No requiere
  cambios en el shader (`pipe_coolant.shader`/`PipeCoolant.tres` ya exponen ambos parámetros por
  instancia vía material duplicado) — el trabajo es en `CoolantFlowAdapter.compute_flow()`, que debe
  llamar `set_flow_speed(normal_flow_speed * flow[i])` y `set_flow_intensity(normal_flow_intensity *
  flow[i])` por tramo en vez del booleano único actual.
- **D4 — Umbral de parche firme.** `firm_patch_pressure_threshold = 0.2` sobre caudal `0..1`
  significa que se puede soldar con un 20 % de caudal. ¿Debe ser 0.0 estricto? `[DECIDIR]`
- **D5 — Válvulas de plasma.** Si FD-257 entra al domo, cinco `CoolantValve` cian más válvulas ámbar
  con la misma animación de 180° es vocabulario en conflicto. FD-255 da la respuesta de color;
  falta decidir si el accionar también cambia (`HoldInteractableV2` ya existe). `[DECIDIR]`

### §11 — Reparto de ejecución

Regla de corte (FD-255 R8): **Jules no toca `.tscn` ni `project.godot`**. Todo lo que es partir
geometría, re-cablear `NodePath` en la escena, o calibrar a ojo es LOCAL. Todo lo que es código puro
—recurso, máquina de barrido, contrato de adapter, tests— es JULES, en paralelo por ser archivos
disjuntos entre sí salvo dependencia declarada.

| # | Tarea | Ejecutor | Archivos | Aceptación | Depende de | Estado |
|---|---|---|---|---|---|---|
| J1 | **`PipeNetworkResource`** (§3): `branches` Dictionary, `validate()` que rechaza NodePath roto, rama sin tanque, rama sin tramos, y `pipe_run` repetido en más de un tramo | JULES | `core_v2/systems/pipe/PipeNetworkResource.gd` (nuevo) | `test_no_cycles` pasa; `validate()` cubre los 4 casos de rechazo listados en §3 | — | pendiente |
| J2 | **`CoolantFlowAdapter` v2** (§4): reemplaza `valves`/`pipe_runs` por `network`+`branch_id`; elimina `circuit_manager_path`/`_manager` (H3); `_resolve_references()` solo en `_ready()`; recálculo por señal (`valve_state_changed`, `state_changed` de la fuga, drenaje del tanque) en vez de `_physics_process` a 60Hz; barrido O(n) de §1 escribiendo `set_flow_speed`/`set_flow_intensity` por tramo escalado por `flow[i]` (D3); nueva API `get_segment_flow(index)`, `is_pressurized_at(node)`; **conservar** `is_flow_active()` como `get_segment_flow(0) > 0.0` — lo sigue leyendo `CoolantLab._update_status()` | JULES | `core_v2/systems/cryo/CoolantFlowAdapter.gd` | `test_flow_prefix_scan`, `test_leak_kills_downstream` pasan; snapshot/restore guarda `Array` de caudales (§8), no `_phase` | J1 | pendiente |
| J3 | **Autoridad del parche** (§4/T5/H6): `LeakPatchPoint.patch_with_gloo()` deja de leer `_manometer`, pregunta `_flow_adapter.is_pressurized_at(leak)`; unificar `firm_patch_pressure_threshold` a escala `0..1` | JULES | `core_v2/systems/cryo/LeakPatchPoint.gd` | `test_firm_patch_requires_zero_flow` pasa | J2 | pendiente |
| J4 | **Fix H5**: en `CoolantLeak`, la transición a `DEPRESSURIZED` deja de depender solo de `valve_path` propio y pasa por el caudal del adapter (vía la señal que ya dispara J2, o `is_pressurized_at`) | JULES | `core_v2/systems/cryo/CoolantLeak.gd` | cerrar `ValveWest_2` (no la que apunta `valve_path`) también despresuriza `LeakWest` | J2 | pendiente |
| J5 | **Tests GdUnit3** de §9 completos (los 5) | JULES | `core_v2/tests/**` (ubicar junto a tests de cryo existentes) | los 5 tests de §9 pasan en CI | J1, J2, J3 | pendiente |
| L1 | **T1/T2 — Partir `PipeRunWest`/`PipeRunEast`** en 4 tramos rectos cada uno (tabla T1), agregar `CryoLoopSink` (T2) | LOCAL | `core_v2/scenes/CoolantLab.tscn` | criterio de aceptación de §6 verificado a ojo: `S3` queda quieto con la fuga activa | — | pendiente |
| L2 | **T3 — Instanciar `PipeNetworkResource`** como `SubResource` en `CoolantLab.tscn` con las dos ramas de 4 tramos | LOCAL | `core_v2/scenes/CoolantLab.tscn` | `validate()` no rechaza nada al cargar la escena | J1, L1 | pendiente |
| L3 | **T4 — Recablear los dos `CoolantFlowAdapter`** a `network`+`branch_id`; recablear `LeakWest.valve_path` → `ValveWest_2` y `LeakEast` análogo (T6); recablear `LeakPatchPoint.flow_adapter_path` (ya está) | LOCAL | `core_v2/scenes/CoolantLab.tscn` | — | J2, J3, J4, L2 | pendiente |
| L4 | **T7 — Retirar manómetro del puzle**: sacar `west_press_ok`/`east_press_ok` de `CoolantLab._update_status()` (o resolver D2 primero: borrar prop / reubicar / dejar de adorno) | LOCAL | `core_v2/scenes/CoolantLab.gd`, `CoolantLab.tscn` | estabilización ya no depende del manómetro | D2, J2 | pendiente, bloqueado por D2 |
| L5 | **Verificación jugable** del criterio de aceptación de §6 con `run-odisea` (screenshot/eval), en las dos ramas y con ambos órdenes de cierre de válvula | LOCAL | — | capturas mostrando `S3` quieto y `S0`/`S1` corriendo tras cerrar `ValveWest_2` | L3 | pendiente |

D2 (destino del `PipeManometer`) sigue abierto y bloquea L4; no bloquea J1-J5 ni L1-L3. D4 (umbral de
parche firme) y D5 (válvulas de plasma) no bloquean esta ronda: D4 es un valor de tuning que J3 deja
como está (`0.2`) salvo que se decida antes; D5 es alcance de FD-257, fuera de este FD.

### §12 — Qué invalida de FDs anteriores

- **FD-264 §4** especifica el manómetro como instrumento de diagnóstico de rama. Con el shader de
  flujo como canal, esa función desaparece. Anotar en FD-264, no dejarlo afirmando lo contrario.
- **FD-266** sigue vigente en su semántica; lo que cambia es **cómo se comunica**: la regla
  "despresurizar para reparar" pasa a leerse en la imagen del caño y no en un dial.
- El comentario de cabecera de `CoolantFlowAdapter.gd` (*"Reads OCLS circuit state"*) es falso hoy y
  debe borrarse junto con `circuit_manager_path`.