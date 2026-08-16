# FD-255 J7 — Niebla de coolant sobre GasArea3D

## Objetivo

La fuga de criocoolant ya tiene su lógica (`CoolantLeak`) y su estación visual, pero la niebla
la está haciendo un `FrostEmitter` puesto como sustituto provisional. El sistema de gas real del
proyecto, `GasArea3D`, quedó replay-safe en la tarea J2 y es el que debe cegar al jugador.

Falta la pieza que los une: un adaptador que traduzca la intensidad de la fuga en densidad de
gas, sin que ninguno de los dos tenga que conocer al otro.

## Contexto

- `core_v2/systems/cryo/CoolantLeak.gd` — máquina de estados de la fuga. Expone
  `get_state()`, `get_leak_intensity() -> float` (0..1, continua) y las señales
  `state_changed(new_state)`, `warning_started()`, `leak_started()`, `leak_sealed()`.
  **Léalo, no lo modifique.**
- `core_v2/systems/gas/GasArea3D.gd` — nube de gas con grid de densidad, empuje y daño.
  Está en el grupo `replay_sync` y tiene `get_snapshot()`/`restore_snapshot()`. Ojo con su API:
  el gas se puebla en `_ready()` y las partículas las administra su hijo `GasParticleManager`
  (`emit_particle`, `emit_burst`, `clear_all`, `get_active_particle_indices`).
  **Léalo, no lo modifique.**
- FD del sistema: `docs/features/FD-256_criocoolant.md`. Regla de diseño que manda: el gas frío
  **ciega, no daña**. Nada de daño por contacto en este sistema.
- Contrato de replay: `AGENTS.md` §5.3.

## Qué implementar

`core_v2/systems/cryo/CoolantFogAdapter.gd` (`extends Spatial`, `class_name CoolantFogAdapter`).

- `export(NodePath) var leak_path` — el `CoolantLeak`.
- `export(NodePath) var gas_path` — el `GasArea3D` que hace de niebla.
- `export(int) var particles_at_full := 90` — cuántas partículas mantiene vivas la nube con la
  fuga al máximo.
- `export(float) var fill_radius := 2.2` y `export(float) var fill_height := 1.4` — el volumen
  que ocupa la niebla alrededor del punto de fuga.
- `export(float) var dissipate_rate := 0.6` — qué tan rápido se vacía la nube al sellar.

Comportamiento, todo en `_physics_process`:

1. Leer `get_leak_intensity()` del leak (si el path no resuelve o el nodo no tiene el método,
   no hacer nada y no crashear).
2. Mantener la población de partículas del gas proporcional a esa intensidad: si faltan, emitir
   las que falten con `emit_particle` / `emit_burst` en posiciones **deterministas** dentro del
   volumen (derivadas de un contador propio, patrón `_hashed_unit` como en
   `core_v2/props/emitters/FrostEmitter.gd`); si sobran, dejar que se apaguen solas o usar
   `clear_all()` cuando la intensidad llega a 0.
3. Emitir a un ritmo acotado por frame (no volcar 90 partículas de golpe): que la nube crezca
   con el mismo ritmo con el que crece la fuga.
4. Asegurar que el gas **no dañe**: si el `GasArea3D` tiene `damage_per_second` distinto de 0,
   ponerlo en 0 en `_ready()` y dejar un comentario diciendo por qué (el coolant ciega, no daña).

## Determinismo

- Grupo `replay_sync`, lógica en `_physics_process`, `get_snapshot()`/`restore_snapshot()` con
  el contador de emisión y el estado del adaptador.
- Nada de `randf()`, `randi()`, `rand_range()` ni `OS.get_ticks_msec()`.

## Test

`core_v2/tests/test_coolant_fog_adapter.gd` (GdUnit3, estilo de `core_v2/tests/test_coolant_leak.gd`):

1. Con la fuga en `LEAKING` y la intensidad subiendo, la cantidad de partículas activas del gas
   crece; con la fuga sellada, decrece hasta 0.
2. La nube nunca aplica daño: `damage_per_second` del gas queda en 0.
3. Dos corridas con los mismos ticks producen exactamente las mismas posiciones de partícula
   (determinismo): comparar `get_active_particle_indices()` y las posiciones resultantes.
4. Snapshot/restore a mitad del llenado reproduce el mismo estado.

## Archivos

**Permitidos:** `core_v2/systems/cryo/CoolantFogAdapter.gd` (nuevo),
`core_v2/tests/test_coolant_fog_adapter.gd` (nuevo).

**Prohibidos:** `core_v2/systems/cryo/CoolantLeak.gd`, `core_v2/systems/gas/**`,
`core_v2/props/**`, cualquier `.tscn`, `project.godot`, y `core_v2/systems/plasma/**`,
`core_v2/systems/atmosphere/**`, `core_v2/systems/auxpower/**` (otras tareas en paralelo).

## Convenciones

- **Godot 3.6, GDScript 1.x.** `yield()`, no `await`. `onready var`. `connect("sig", self, "_m")`.
- Tipado estático, miembros internos con `_`, cada `export var` documentado.
- El archivo, por debajo de 200 líneas.

## Aceptación

```bash
./runtest.sh -a ./core_v2/tests/test_coolant_fog_adapter.gd
./runtest.sh -a ./core_v2/tests/test_coolant_leak.gd
./runtest.sh -a ./core_v2/tests/test_hazard_determinism.gd
```

## Qué NO hacer

- No crear escenas ni props: esto es solo el adaptador y su test.
- No agregar daño al gas frío.
- No modificar `GasArea3D` ni `CoolantLeak`: si le falta una API, dígalo en el reporte en vez de
  editarlos.

## Entrega

Cuando termines, **publicá el pull request** contra la rama `feature/FD-255-ship-systems`.
El PR es la vía de integración: un changeset suelto obliga a aplicar el patch a mano.
