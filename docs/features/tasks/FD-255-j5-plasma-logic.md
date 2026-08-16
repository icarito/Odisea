# FD-255 J5 — Sistema Plasma: lógica

## Objetivo

El plasma es la energía de alta temperatura de la nave (FD-255 / FD-257). Su fallo es una
**barrera de daño**: un chorro que corta el paso. Su aviso es siempre el mismo orden —
la tubería brilla más, sube un zumbido, y recién entonces sale el chorro. Se libera
**redirigiendo el flujo** por una conducción sana.

Implementar **la lógica**, determinista y testeable headless. Sin geometría, sin materiales,
sin escenas.

## Contexto

- FD del sistema: `docs/features/FD-257_plasma.md`.
- **Patrón obligatorio a seguir:** `core_v2/systems/cryo/CoolantLeak.gd`. El plasma es el
  sistema hermano del criocoolant: misma forma (máquina de estados con aviso previo,
  intensidad continua, señales por transición, snapshot), distinto desenlace (daña en vez de
  cegar, y se libera reordenando el circuito en vez de cerrando una válvula). Léalo primero.
- El daño ambiental ya existe y **ya es replay-safe**: `core_v2/systems/gas/GasArea3D.gd`
  (grupo `replay_sync`, snapshot, `damage_per_second`, `is_flammable`) y
  `core_v2/props/emitters/FireEmitter.gd` (daño en `_physics_process`). **Esta tarea no los
  edita ni los instancia**: solo expone el estado para que la escena los active.
- Contrato de replay: `AGENTS.md` §5.3.
- `PipeValve` (`core_v2/props/pipe/PipeValve.gd`) hereda `InteractableBaseV2`, emite
  `valve_state_changed(is_open)` y tiene snapshot. Es la pieza con la que el jugador reordena
  el flujo. **Léala, no la modifique.**

## Qué implementar

### 1. `core_v2/systems/plasma/PlasmaConduit.gd` (`extends Spatial`, `class_name PlasmaConduit`)

```gdscript
enum State { NOMINAL, OVERHEATING, VENTING, REROUTED }
```

- `NOMINAL` — flujo sano.
- `OVERHEATING` — el aviso: dura `warning_duration`. Exponer `get_warning_progress() -> float`
  (0→1) para que el visual suba brillo y el audio suba el zumbido.
- `VENTING` — el fallo: chorro de plasma activo. `get_hazard_intensity() -> float` (0→1 en
  `ramp_up_duration`) manda la barrera de daño.
- `REROUTED` — el flujo se desvió: la barrera se apaga en `shutdown_duration` y vuelve a
  `NOMINAL`.

Señales: `state_changed(new_state)`, `overheat_started()`, `vent_started()`, `flow_rerouted()`.
API: `trigger_overheat()`, `reroute()`, `set_active(bool)` (true = disparar, false = redirigir,
igual que en `CoolantLeak`), `reset()`, `get_state()`.

Exportadas documentadas: `starts_overheating := false`, `warning_duration := 3.0`,
`ramp_up_duration := 1.5`, `shutdown_duration := 2.0`.

### 2. Puzzle de redirección: `core_v2/systems/plasma/PlasmaRoute.gd`

El mini-game de liberación del FD-257, en su forma más simple y determinista:

- `export(Array, NodePath) var valve_paths` — las válvulas que el jugador gira.
- `export(PoolIntArray) var required_pattern` — el estado (0/1) que debe tener cada válvula para
  que la ruta sea segura.
- Se conecta a `valve_state_changed` de cada válvula. Cuando el patrón completo coincide, llama
  `reroute()` en el `PlasmaConduit` indicado por `conduit_path` y emite `route_solved()`.
  Si deja de coincidir, emite `route_broken()` y vuelve a `trigger_overheat()`.
- Tolerante: paths que no resuelven se ignoran sin crashear.

### 3. Determinismo

Ambos scripts: grupo `replay_sync`, lógica en `_physics_process`, `get_snapshot()` /
`restore_snapshot()` con el estado completo (estado, temporizador, intensidad, patrón actual).
Sin `randf()`.

## Test

`core_v2/tests/test_plasma_conduit.gd` (GdUnit3, estilo de `test_coolant_leak.gd`):

1. Ciclo por tiempo: `NOMINAL → OVERHEATING → VENTING`, con `hazard_intensity` llegando a 1.0 y
   `warning_progress` avanzando de 0 a 1 durante el aviso.
2. El aviso siempre precede al daño: en `OVERHEATING`, `get_hazard_intensity()` es 0.
3. `reroute()` durante `VENTING` → `REROUTED` → la intensidad baja a 0 → `NOMINAL`.
4. `PlasmaRoute` con tres válvulas simuladas: al alcanzar el patrón pedido llama `reroute()`;
   al romperlo vuelve a disparar el aviso.
5. Snapshot/restore a mitad del ciclo reproduce estado e intensidad exactos.

## Archivos

**Permitidos:** `core_v2/systems/plasma/**` (nuevo), `core_v2/tests/test_plasma_conduit.gd` (nuevo).

**Prohibidos:** cualquier `.tscn`, `project.godot`, `core_v2/systems/gas/**`,
`core_v2/props/**`, `core_v2/systems/cryo/**`, `core_v2/systems/auxpower/**`,
`core_v2/systems/atmosphere/**` (otras tareas en paralelo).

## Convenciones

- **Godot 3.6, GDScript 1.x.** `yield()`, no `await`. `onready var`. `connect("sig", self, "_m")`.
- Tipado estático, miembros internos con `_`, cada `export var` documentado.
- Cada archivo por debajo de 200 líneas.

## Aceptación

```bash
./runtest.sh -a ./core_v2/tests/test_plasma_conduit.gd
./runtest.sh -a ./core_v2/tests/test_coolant_leak.gd   # el sistema hermano sigue en pie
```

## Qué NO hacer

- No crear escenas, partículas ni materiales. El chorro lo dibuja la escena, no este código.
- No aplicar daño directamente al jugador: exponga la intensidad y deje que la zona de daño ya
  existente (`GasArea3D` / `FireEmitter`) lo haga.
- No duplicar `CoolantLeak`: seguir su forma, no copiar su archivo entero.

## Entrega

Cuando termines, **publicá el pull request** contra la rama `feature/FD-255-ship-systems`.
El PR es la vía de integración: un changeset suelto obliga a aplicar el patch a mano.
