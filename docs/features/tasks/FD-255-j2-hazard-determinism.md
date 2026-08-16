# FD-255 J2 — Peligros ambientales deterministas

## Objetivo

Los peligros ambientales de los cuatro sistemas de la nave (FD-255) — niebla de coolant, barrera
de plasma, fuego — se apoyan en `GasArea3D` y en los emisores de `core_v2/props/emitters/`. Tres
de esas piezas rompen el contrato de replay determinista del proyecto (`AGENTS.md` §5.3):

1. `GasArea3D` no guarda ni restaura su estado.
2. `FireEmitter` aplica daño desde `_process`, o sea daño dependiente de los FPS.
3. `LeakEmitter` es no determinista por diseño y no está documentado como tal, así que se usa
   por error donde hace falta determinismo.

Esta tarea arregla los tres.

## Contexto

- Contrato de replay: `AGENTS.md` §5.3. Todo agente sincronizado pertenece al grupo
  `replay_sync`, implementa `restore_snapshot(data: Dictionary)` y corre su lógica en
  `_physics_process`, **nunca** en `_process`.
- Referencia de un snapshot bien hecho en este mismo subsistema:
  `core_v2/systems/gas/GasParticleManager.gd` (`get_snapshot` / `restore_snapshot`, líneas ~548
  en adelante). Es el manager de partículas que ya cumple el contrato: cópiele el estilo.
- Referencia de ruido determinista: `core_v2/props/emitters/FrostEmitter.gd` tiene
  `_hashed_unit(index)`, que genera variación reproducible a partir de un contador en vez de
  `randf()`. Es exactamente el patrón que hay que replicar.

## Parte A — `GasArea3D` replay-safe

Archivo: `core_v2/systems/gas/GasArea3D.gd` (429 líneas).

Estado actual verificado: corre en `_physics_process` (bien), pero **no** está en `replay_sync` y
**no** tiene `get_snapshot()` / `restore_snapshot()`.

1. En `_ready()`, `add_to_group("replay_sync")`.
2. `get_snapshot() -> Dictionary` con el estado que hace falta para reproducir la nube:
   - `_grid` (densidad por celda) y `_cell_particles` en forma serializable.
   - `_burning_cells` (qué celdas están en combustión).
   - `_density_tick` (el contador que escalona el recálculo cada `density_update_interval`).
   - **No** serializar los nodos de `_bodies_inside`: son referencias vivas. Si necesita
     recordar que había cuerpos adentro, guarde solo lo que sea reconstruible, o deje que el
     `Area` los vuelva a detectar; documente la decisión en un comentario.
3. `restore_snapshot(data: Dictionary) -> void` que reponga esos campos con tolerancia: si el
   tamaño del grid cambió (otra `grid_resolution`), no crashear — reconstruir el grid y salir.
4. No cambiar el modelo de simulación ni los valores por defecto exportados. Solo guardar y
   restaurar.

## Parte B — `FireEmitter` en el reloj de física

Archivo: `core_v2/props/emitters/FireEmitter.gd` (113 líneas).

Estado actual verificado: `_ready()` ya lo agrega a `replay_sync` y ya tiene
`get_snapshot`/`restore_snapshot` — pero toda la lógica vive en `_process(delta)`, incluido
`emit_signal("damage_tick", damage_per_tick)`. Eso hace el daño dependiente de los FPS.

1. Mover el cuerpo de `_process(delta)` a `_physics_process(delta)`. Mantener el guard
   `if Engine.editor_hint: return`.
2. Reemplazar el ruido de `_spawn_flame_particle()`: hoy usa `randf()` dos veces para el offset
   de cada partícula, y esas partículas entran al pool de `GasParticleManager`, **que sí se
   snapshotea** — o sea, ruido no reproducible contaminando estado sincronizado. Derivarlo de un
   contador interno con el patrón `_hashed_unit(index)` de `FrostEmitter` (agregue el contador
   al snapshot para que sobreviva un restore).
3. `FrostEmitter` ya hace el daño en `_physics_process` y no usa `randf()`: es el modelo a
   seguir. Si algo suyo sirve para no duplicar lógica, reutilícelo, pero **no** refactorice
   `FrostEmitter` en esta tarea.
4. `Dome_Intro_Fire.tscn` usa este emisor: no cambie sus propiedades exportadas ni los nombres de
   nodos hijos (`GasParticleManager`, `CollisionShape`), o la escena se rompe.

## Parte C — `LeakEmitter` declarado decorativo

Archivo: `core_v2/props/emitters/LeakEmitter.gd` (209 líneas).

Estado actual verificado: corre en `_process`, usa `rand_range` en los intervalos de burst, no
está en `replay_sync` y no tiene snapshot. **No lo convierta en determinista**: su rol es el
*aviso* visual (vapor, condensación), no el peligro con consecuencia.

Agregue un comentario de cabecera corto y explícito, en el estilo de los comentarios que ya
tiene el archivo, diciendo: que es decorativo y no determinista, que no debe usarse para
gameplay con consecuencia (daño, bloqueo de ruta), y que para eso están `FireEmitter` /
`FrostEmitter` / `GasArea3D`, que sí cumplen el contrato de replay. Nada más: **cero cambios de
comportamiento en este archivo.**

## Test

Agregue `core_v2/tests/test_hazard_determinism.gd` (GdUnit3), siguiendo el estilo de los tests
que ya existen en `core_v2/tests/`. Debe cubrir:

- `GasArea3D`: poblar la nube, correr N ticks de `_physics_process` con delta fijo (`1.0/60.0`),
  tomar snapshot, seguir, restaurar, y verificar que la densidad de las celdas coincide.
- `FireEmitter`: con el emisor activo y un cuerpo del grupo `player` adentro, verificar que la
  cantidad de `damage_tick` emitidos en un tiempo simulado dado **no** depende del número de
  llamadas a `_process` (o sea, que el daño lo dispara la física).

## Archivos

**Permitidos** (solo estos):
- `core_v2/systems/gas/GasArea3D.gd`
- `core_v2/props/emitters/FireEmitter.gd`
- `core_v2/props/emitters/LeakEmitter.gd` (solo el comentario de cabecera)
- `core_v2/tests/test_hazard_determinism.gd` (nuevo)

**Prohibidos:** cualquier `.tscn`, `project.godot`, `core_v2/systems/gas/GasParticleManager.gd`,
`core_v2/props/emitters/FrostEmitter.gd`, `core_v2/systems/circuit/**` y
`core_v2/systems/cryo/**` (hay otras tareas trabajando ahí en paralelo).

## Convenciones del proyecto

- **Godot 3.6, GDScript 1.x.** `yield()`, no `await`. `onready var`, no `@onready`.
  `connect("signal", self, "_metodo")` con strings.
- Tipado estático en código nuevo: `func f(v: float) -> void:`, `var x: int = 0`.
- El proyecto renderiza en **GLES2**: nada de nodos `Particles` (GPU). Las partículas de gas van
  por `GasParticleManager` (MultiMesh), que ya está resuelto — no lo cambie.
- Cambios chicos y enfocados. No reescribir archivos completos ni reordenar lo que funciona.
- Nada de `randf()`, `randi()`, `rand_range()` ni `Engine.get_frames_drawn()` en lógica
  sincronizada.

## Aceptación

```bash
./runtest.sh -a ./core_v2/tests/test_hazard_determinism.gd   # el test nuevo pasa
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd       # el contrato global sigue en pie
```

El output de los tests queda en `./reports/gdunit_runner.log`.

## Qué NO hacer

- No rediseñar la simulación de gas ni tocar sus parámetros de tuning exportados.
- No convertir `LeakEmitter` en determinista (es decorativo a propósito).
- No crear props, escenas ni materiales: esta tarea es solo lógica y tests.

## Entrega

Cuando termines, **publicá el pull request** contra la rama `feature/FD-255-ship-systems`.
El PR es la vía de integración: un changeset suelto obliga a aplicar el patch a mano.
