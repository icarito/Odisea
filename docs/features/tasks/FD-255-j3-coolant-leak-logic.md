# FD-255 J3 — Sistema Criocoolant: lógica de la fuga

## Objetivo

El criocoolant es el primero de los cuatro sistemas de la nave (FD-255 / FD-256): el refrigerante
que mantiene fríos los criopods. Su ciclo de juego es siempre el mismo patrón legible:

```
SANO  →  AVISO (condensación)  →  FALLO (niebla que ciega)  →  LIBERADO (válvula cerrada)
```

Hay que implementar **la lógica de ese ciclo**, determinista y testeable headless, en un archivo
nuevo. La parte visual (tuberías, pluma, volumen de niebla, materiales) la hace otra persona
después, colgándose de la API que usted deje. **Esta tarea no crea geometría, materiales ni
escenas.**

## Contexto

- FD del sistema: `docs/features/FD-256_criocoolant.md`. FD maestro: `docs/features/FD-255_systems_master.md`.
- Regla de diseño que manda: el fallo del coolant **ciega, no daña**. Es el respiro del juego:
  sin timer agresivo, sin enemigo. El jugador aprende *condensación = salí de acá o te quedás
  ciego*, y cerrar la válvula lo resuelve.
- El aviso siempre ocurre **antes** del fallo y en el mismo orden. Esa previsibilidad es el
  punto: es lo que permite que el jugador anticipe sin texto.
- Contrato de replay determinista: `AGENTS.md` §5.3 — grupo `replay_sync`,
  `restore_snapshot(data: Dictionary)`, lógica en `_physics_process`, sin `randf()`.
- Referencias de estilo para el snapshot, en este repo:
  `core_v2/props/emitters/FrostEmitter.gd` y `core_v2/props/pipe/PipeValve.gd`.

## Qué implementar

Un archivo nuevo: `core_v2/systems/cryo/CoolantLeak.gd`, `extends Spatial`, con
`class_name CoolantLeak`.

### Máquina de estados

```gdscript
enum State { HEALTHY, WARNING, LEAKING, SEALED }
```

- `HEALTHY` — sistema sano. No pasa nada.
- `WARNING` — condensación: el aviso. Dura `warning_duration` segundos y después pasa solo a
  `LEAKING`.
- `LEAKING` — fuga activa. `leak_intensity` sube de 0 a 1 en `ramp_up_duration` segundos y se
  queda ahí.
- `SEALED` — la válvula se cerró. `leak_intensity` baja de donde esté a 0 en `dissipate_duration`
  segundos; al llegar a 0 vuelve a `HEALTHY`.

Sellar durante `WARNING` cancela el aviso y vuelve a `HEALTHY` sin pasar por `LEAKING`
(recompensa al jugador atento).

### Variables exportadas

Todas documentadas para el Inspector, con tipo y valor por defecto razonable:

- `export(bool) var starts_leaking := false` — arranca en `WARNING` en vez de `HEALTHY`.
- `export(float) var warning_duration := 4.0`
- `export(float) var ramp_up_duration := 3.0`
- `export(float) var dissipate_duration := 5.0`
- `export(bool) var auto_restart := false` — si es `true`, tras `SEALED → HEALTHY` la fuga puede
  volver a dispararse por llamada externa; nunca se dispara sola por tiempo.

### API pública

- `func get_state() -> int` — el `State` actual.
- `func get_leak_intensity() -> float` — 0.0 a 1.0. **Esta es la variable que va a leer la capa
  visual** para la densidad de la niebla y el brillo de la pluma. Que sea continua y suave.
- `func trigger_leak() -> void` — dispara el ciclo desde `HEALTHY` (entra en `WARNING`).
- `func seal() -> void` — cierra la fuga: `WARNING` → `HEALTHY`, `LEAKING` → `SEALED`.
- `func set_active(value: bool) -> void` — para que el `LogicCircuitManager` pueda manejarlo como
  un prop más del circuito: `true` = `trigger_leak()`, `false` = `seal()`.
- `func reset() -> void` — vuelve a `HEALTHY` con intensidad 0.

### Señales

- `signal state_changed(new_state)` — en cada transición.
- `signal warning_started()`
- `signal leak_started()`
- `signal leak_sealed()`

La capa visual y el audio se enganchan a estas señales; no las use usted para lógica de estado.

### Determinismo

- `_ready()`: `add_to_group("replay_sync")`.
- Toda la lógica de tiempo en `_physics_process(delta)`. Nada en `_process`.
- `get_snapshot() -> Dictionary` / `restore_snapshot(data: Dictionary) -> void` con el estado
  completo: estado actual, temporizador del estado, e intensidad.
- Sin `randf()`, `randi()`, `rand_range()` ni `OS.get_ticks_msec()` en la lógica.

### Integración (solo lo que le toca)

- **Con la válvula:** `PipeValve` (`core_v2/props/pipe/PipeValve.gd`) hereda de
  `InteractableBaseV2` y emite `valve_state_changed(is_open)`. Deje un
  `export(NodePath) var valve_path` opcional: si está seteado, conéctese a esa señal en `_ready()`
  y llame `seal()` cuando la válvula se cierre. Si no está seteado, no pasa nada — el circuito o
  la escena lo manejarán por afuera.
- **Con la niebla:** **no** toque `GasArea3D` ni `GasParticleManager`. Hay otra tarea editando
  `GasArea3D` en paralelo. La conexión fuga → niebla se hace después, en la escena, leyendo
  `get_leak_intensity()`. Su trabajo termina en exponer esa intensidad.

## Test

`core_v2/tests/test_coolant_leak.gd` (GdUnit3, estilo de los tests que ya viven en
`core_v2/tests/`). Debe cubrir:

1. El ciclo completo por tiempo: `HEALTHY → WARNING → LEAKING`, avanzando con `_physics_process`
   a delta fijo (`1.0 / 60.0`), verificando las transiciones y que `leak_intensity` llega a 1.0.
2. `seal()` durante `WARNING` vuelve a `HEALTHY` sin pasar por `LEAKING`.
3. `seal()` durante `LEAKING` pasa a `SEALED`, la intensidad decae a 0 y termina en `HEALTHY`.
4. Determinismo: snapshot a mitad del ciclo, seguir corriendo, restaurar, correr los mismos ticks
   y verificar que estado e intensidad coinciden exactamente.

## Archivos

**Permitidos** (solo estos):
- `core_v2/systems/cryo/CoolantLeak.gd` (nuevo)
- `core_v2/tests/test_coolant_leak.gd` (nuevo)

**Prohibidos:** cualquier `.tscn`, `project.godot`, `core_v2/systems/gas/**`,
`core_v2/props/emitters/**`, `core_v2/systems/circuit/**`, `core_v2/props/pipe/**` (hay otras
tareas trabajando ahí en paralelo). Se puede **leer** `PipeValve.gd` para conectarse a su señal,
pero no modificarlo.

## Convenciones del proyecto

- **Godot 3.6, GDScript 1.x.** `yield()`, no `await`. `onready var`, no `@onready`.
  `connect("signal", self, "_metodo")` con strings.
- Tipado estático: `func f(v: float) -> void:`, `var x: int = 0`. Miembros internos con `_`.
- Todo el código nuevo va en `core_v2/`.
- Componentes chicos: este archivo debe quedar bien por debajo de 200 líneas, haciendo una sola
  cosa.
- Documentar cada `export var` con un comentario para el Inspector.

## Aceptación

```bash
./runtest.sh -a ./core_v2/tests/test_coolant_leak.gd
```

El output queda en `./reports/gdunit_runner.log`.

## Qué NO hacer

- No crear escenas, mallas CSG, materiales, luces ni partículas. Cero visual.
- No inventar un sistema de interacción nuevo: la válvula ya existe y hereda `InteractableBaseV2`.
- No agregar daño al jugador: el coolant **ciega, no daña**.
- No meter un timer que dispare la fuga solo: la fuga la dispara el nivel o el circuito.

## Entrega

Cuando termines, **publicá el pull request** contra la rama `feature/FD-255-ship-systems`.
El PR es la vía de integración: un changeset suelto obliga a aplicar el patch a mano.
