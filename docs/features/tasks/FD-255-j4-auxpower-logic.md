# FD-255 J4 — Sistema Energía Auxiliar: lógica

## Objetivo

La energía auxiliar es el respaldo de emergencia de la nave (FD-255 / FD-259): cuando falta,
las puertas quedan selladas. Su fallo **no hace daño, bloquea ruta**, y se libera accionando un
lever o una secuencia de paneles.

Implementar **la lógica**, determinista y testeable headless. Sin geometría, sin materiales, sin
escenas: la estación visual la arma otra persona colgándose de esta API.

## Contexto

- FD del sistema: `docs/features/FD-259_energia_auxiliar.md`.
- El pegamento del proyecto ya existe y **ya es replay-safe**: `LogicCircuitManager`
  (`core_v2/systems/circuit/LogicCircuitManager.gd`) ejecuta grafos por ticks con compuertas
  AND/OR/XOR/NOT/DELAY, y desde FD-255 J1 tiene `get_snapshot()`/`restore_snapshot()` y grupo
  `replay_sync`. **Úselo, no escriba un motor de lógica nuevo.**
- Documentación: `docs/interaction/CIRCUIT_SYSTEM.md`, `core_v2/systems/circuit/README.md`.
- Contrato de replay: `AGENTS.md` §5.3 (grupo `replay_sync`, `restore_snapshot`, lógica en
  `_physics_process`, sin `randf()`).
- Patrón de referencia recién incorporado, sígalo de cerca:
  `core_v2/systems/cryo/CoolantLeak.gd` — máquina de estados con señales por transición,
  intensidad continua para que lo visual se cuelgue, snapshot y `set_active()` para el circuito.

## Qué implementar

### 1. `core_v2/systems/auxpower/AuxPowerBus.gd` (`extends Spatial`, `class_name AuxPowerBus`)

El estado del respaldo de un sector.

```gdscript
enum State { POWERED, OFFLINE, RESTORING }
```

- `OFFLINE` — sin energía: lo que dependa de este bus queda bloqueado. Es el estado de fallo.
- `RESTORING` — se accionó el lever / se completó la secuencia; la energía sube durante
  `restore_duration` segundos.
- `POWERED` — régimen normal.

Exportadas (documentadas para el Inspector): `starts_offline := true`,
`restore_duration := 2.5`, `flicker_period := 0.8` (cadencia del aviso; ver abajo).

API pública:
- `get_state() -> int`, `get_power_level() -> float` (0.0 a 1.0, continua — la usa el visual
  para el brillo del panel y la lectura OD-02).
- `is_powered() -> bool` (true solo en `POWERED`).
- `request_restore()` / `cut_power()`.
- `set_active(value: bool)` — para que el `LogicCircuitManager` lo maneje como un prop más.
- Señales: `state_changed(new_state)`, `power_restored()`, `power_lost()`.
- **Aviso legible:** mientras está `OFFLINE`, exponer `get_flicker_phase() -> float` (0..1,
  derivada del tiempo acumulado en el estado, determinista) para que la lectura OD-02 parpadee.
  No cree ningún nodo visual: solo el número.

### 2. `core_v2/systems/auxpower/SealedDoorLock.gd` (`extends Spatial`)

El puente entre el bus y una puerta ya existente. Exporta `bus_path: NodePath` y
`door_path: NodePath`. Cuando el bus pasa a `POWERED` llama `set_active(true)` en la puerta (o
`open()` si no tiene `set_active`); cuando cae, la vuelve a sellar. Tolerante: si el path no
resuelve o el nodo no tiene el método, no crashea.

Las puertas del proyecto (`core_v2/props/doors/HeavyBlastDoor.tscn`, `VerticalDoor.tscn`)
heredan de `InteractableBaseV2`, que expone `set_active(bool)`. **Léalas, no las modifique.**

### 3. Grafo de ejemplo: `core_v2/systems/circuit/examples/AuxPowerSequence.gd`

Un script corto que **construye por código** un `CircuitGraphResource` de ejemplo:
tres paneles (props) → compuerta AND → el bus de energía. Sirve de documentación ejecutable de
cómo se arma la secuencia de recalibración del FD-259, y lo usa el test. No cree escenas.

### 4. Determinismo

Todo en `_physics_process`, grupo `replay_sync`, `get_snapshot()`/`restore_snapshot()` con el
estado completo (estado, temporizador, nivel de energía). Sin `randf()` ni `OS.get_ticks_msec()`.

## Test

`core_v2/tests/test_auxpower.gd` (GdUnit3, estilo de `core_v2/tests/test_coolant_leak.gd`):

1. Arranca `OFFLINE`; `is_powered()` es false y el flicker avanza de forma determinista.
2. `request_restore()` → `RESTORING` → tras `restore_duration` → `POWERED`, con `power_level`
   subiendo de 0 a 1.
3. `SealedDoorLock` abre una puerta simulada al recuperar energía y la vuelve a sellar al perderla.
4. Snapshot a mitad de `RESTORING`, seguir, restaurar, repetir los mismos ticks: mismo resultado.
5. La secuencia de tres paneles vía `LogicCircuitManager` alimenta el bus: con los tres paneles
   activos el bus recibe `set_active(true)`; con dos, no.

## Archivos

**Permitidos:** `core_v2/systems/auxpower/**` (nuevo),
`core_v2/systems/circuit/examples/AuxPowerSequence.gd` (nuevo),
`core_v2/tests/test_auxpower.gd` (nuevo).

**Prohibidos:** cualquier `.tscn`, `project.godot`, `core_v2/systems/circuit/LogicCircuitManager.gd`
(úselo, no lo edite), `core_v2/props/**`, `core_v2/systems/cryo/**`, `core_v2/systems/plasma/**`,
`core_v2/systems/atmosphere/**` (hay otras tareas ahí en paralelo).

## Convenciones

- **Godot 3.6, GDScript 1.x.** `yield()`, no `await`. `onready var`. `connect("sig", self, "_m")`.
- Tipado estático, miembros internos con `_`, cada `export var` documentado.
- Componentes chicos: cada archivo por debajo de 200 líneas, haciendo una sola cosa.
- Todo el código nuevo va en `core_v2/`.

## Aceptación

```bash
./runtest.sh -a ./core_v2/tests/test_auxpower.gd
./runtest.sh -a ./core_v2/tests/test_circuit_determinism.gd   # no romper el pegamento
```

## Qué NO hacer

- No crear escenas, mallas, materiales ni luces.
- No escribir un sistema de lógica paralelo al `LogicCircuitManager`.
- No agregar daño: este sistema bloquea ruta, no lastima.
