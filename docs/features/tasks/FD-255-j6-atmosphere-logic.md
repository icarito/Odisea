# FD-255 J6 — Sistema Atmósfera: lógica

## Objetivo

La atmósfera es la presión y el aire de un sector (FD-255 / FD-258). Su fallo es la
**sobrepresión**: una explosión ambiental que no mata de golpe pero mueve — empuja al jugador,
abre pasajes, cierra otros. Su aviso es siempre el mismo orden: parpadeo, chispa, boom. Se
libera **purgando la presión** con un dial que hay que llevar a la zona estable.

Implementar **la lógica**, determinista y testeable headless. Sin geometría, sin materiales,
sin escenas, sin partículas.

## Contexto

- FD del sistema: `docs/features/FD-258_atmosfera.md`.
- **Patrón obligatorio a seguir:** `core_v2/systems/cryo/CoolantLeak.gd` (máquina de estados con
  aviso previo, magnitud continua, señales por transición, snapshot, `set_active()`). Léalo
  primero: los cuatro sistemas de la nave tienen la misma forma a propósito.
- Las esclusas y compuertas ya existen: `core_v2/props/doors/AirlockChamber.tscn`,
  `IrisDoorV2.tscn`, `VerticalDoor.tscn`, y `core_v2/systems/AirlockPool.gd`. Heredan de
  `InteractableBaseV2` (`set_active(bool)`). **Léalas, no las modifique.**
- Contrato de replay: `AGENTS.md` §5.3.

## Qué implementar

### 1. `core_v2/systems/atmosphere/PressureSection.gd` (`extends Spatial`, `class_name PressureSection`)

```gdscript
enum State { NOMINAL, RISING, CRITICAL, VENTED }
```

- `NOMINAL` — presión estable.
- `RISING` — el aviso largo: dura `warning_duration`. `get_pressure() -> float` sube de 1.0 a
  `critical_pressure`. Exponer `get_alarm_phase() -> float` (0..1, determinista, derivada del
  tiempo en el estado) para el parpadeo del manómetro.
- `CRITICAL` — la chispa: ventana corta (`spark_duration`) antes del estallido. Es la última
  oportunidad de purgar.
- Al agotarse `CRITICAL`, emite `blowout(radius, force)` **una sola vez** y pasa a `VENTED`.
  La explosión es un evento lógico: quien la escuche aplica el empuje y dibuja el efecto. Este
  script no toca cuerpos ni crea partículas.
- `VENTED` — presión liberada, vuelve a `NOMINAL` en `recover_duration`.

Señales: `state_changed(new_state)`, `alarm_started()`, `spark_started()`,
`blowout(radius, force)`, `pressure_stabilized()`.
API: `raise_pressure()`, `purge()`, `set_active(bool)` (true = subir presión, false = purgar),
`get_state()`, `get_pressure()`, `is_sealed() -> bool` (true mientras no esté `NOMINAL`: una
esclusa con sobrepresión no debe abrir).

Exportadas documentadas: `starts_rising := false`, `warning_duration := 8.0`,
`spark_duration := 2.5`, `recover_duration := 3.0`, `critical_pressure := 2.4`,
`blowout_radius := 6.0`, `blowout_force := 12.0`.

### 2. Mini-game de purga: `core_v2/systems/atmosphere/PurgeDial.gd`

El dial de sintonía del FD-258, determinista:

- `export(float) var value := 0.0` en 0..1, movido por el jugador con `nudge(delta_value)`
  (lo llamará un interactuable; esta tarea no crea el prop).
- `export(float) var target := 0.62` y `export(float) var tolerance := 0.06`: la zona verde.
- Cuando `value` entra en la zona y se mantiene `hold_duration` segundos (export, 1.2 por
  defecto), llama `purge()` en la `PressureSection` de `section_path` y emite `dial_locked()`.
  Si sale antes, emite `dial_slipped()` y el contador se reinicia.
- Exponer `get_proximity() -> float` (1.0 en el centro de la zona, 0.0 lejos) para que el visual
  y el audio suban de tono al acercarse: es el feedback sensorial que pide el FD.
- Sin timer agresivo: si el jugador no acierta, no pasa nada malo por sí solo.

### 3. Determinismo

Ambos: grupo `replay_sync`, lógica en `_physics_process`, `get_snapshot()`/`restore_snapshot()`
con estado completo (estado, temporizadores, presión, valor y retención del dial). Sin `randf()`.
`blowout` se emite exactamente una vez por ciclo, incluso si se restaura un snapshot tomado
justo antes: el snapshot debe recordar si ya estalló.

## Test

`core_v2/tests/test_pressure_section.gd` (GdUnit3, estilo de `test_coolant_leak.gd`):

1. Ciclo completo por tiempo: `NOMINAL → RISING → CRITICAL → blowout → VENTED → NOMINAL`,
   verificando que `blowout` se emitió **una sola vez** y que la presión sube y baja.
2. El orden del aviso se respeta: en `RISING` no hay chispa, en `CRITICAL` todavía no hay boom.
3. `purge()` durante `RISING` y durante `CRITICAL` estabiliza sin estallar.
4. `is_sealed()` es true fuera de `NOMINAL` (la esclusa no abre con sobrepresión).
5. `PurgeDial`: entrar en la zona y sostener `hold_duration` dispara la purga; salir antes la
   reinicia; `get_proximity()` crece al acercarse al centro.
6. Snapshot/restore a mitad de `CRITICAL` no duplica el `blowout`.

## Archivos

**Permitidos:** `core_v2/systems/atmosphere/**` (nuevo),
`core_v2/tests/test_pressure_section.gd` (nuevo).

**Prohibidos:** cualquier `.tscn`, `project.godot`, `core_v2/props/**`,
`core_v2/systems/AirlockPool.gd`, `core_v2/systems/cryo/**`, `core_v2/systems/plasma/**`,
`core_v2/systems/auxpower/**` (otras tareas en paralelo).

## Convenciones

- **Godot 3.6, GDScript 1.x.** `yield()`, no `await`. `onready var`. `connect("sig", self, "_m")`.
- Tipado estático, miembros internos con `_`, cada `export var` documentado.
- Cada archivo por debajo de 200 líneas.

## Aceptación

```bash
./runtest.sh -a ./core_v2/tests/test_pressure_section.gd
./runtest.sh -a ./core_v2/tests/test_coolant_leak.gd
```

## Qué NO hacer

- No aplicar el empuje ni el daño de la explosión: emita la señal con radio y fuerza, y que la
  escena decida. El jugador no debe morir de un golpe.
- No crear props, escenas ni efectos.
- No tocar el sistema de esclusas existente.

## Entrega

Cuando termines, **publicá el pull request** contra la rama `feature/FD-255-ship-systems`.
El PR es la vía de integración: un changeset suelto obliga a aplicar el patch a mano.
