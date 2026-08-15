# FD-255 J8 — FireEmitter direccional para barrera de plasma

## Objetivo

`FireEmitter` es el peligro reutilizable de fuego del proyecto. En la estación de plasma
de FD-257 se usa como barrera de daño, pero hoy todas sus partículas nacen estáticas y solo
suben por buoyancy: visualmente parece una hoguera/lava vertical, no un chorro de plasma que
sale del nozzle. Agregar una opción **direccional** determinista para que una escena pueda
dar velocidad inicial a las partículas del emisor.

## Contexto

- `core_v2/props/emitters/FireEmitter.gd` ya pertenece a `replay_sync`, simula en
  `_physics_process` y guarda el contador de emisión y el snapshot del `GasParticleManager`.
- `GasParticleManager.emit_particle(local_position, local_velocity, ...)` ya acepta una
  velocidad local y guarda/restaura esa velocidad. No editarlo.
- La escena de plasma aplicará la nueva export después de esta tarea. No edite escenas ni
  materiales: este cambio debe ser una capacidad genérica, no una decisión visual local.
- El comportamiento existente de fuego debe ser idéntico cuando la opción nueva se queda en
  su valor por defecto.

## Qué implementar

1. En `FireEmitter.gd`, agregar una export `jet_velocity: Vector3` con valor por defecto
   `Vector3.ZERO`, documentada como velocidad local inicial de las partículas. `ZERO` mantiene
   exactamente el fuego vertical actual (la gravedad/buoyancy sigue haciendo su trabajo).
2. En `_spawn_flame_particle()`, pasar esa velocidad a `GasParticleManager.emit_particle()`.
   Duplicar el Vector3 al pasarlo no es necesario; no normalizarlo ni alterar su magnitud.
3. No mover ni reescalar el punto de spawn y no agregar aleatoriedad. La escena podrá colocar
   el emisor donde corresponde; esta tarea solo controla la velocidad inicial.
4. Crear `core_v2/tests/test_fire_emitter_jet.gd`, GdUnit3, que demuestre:
   - el valor por defecto emite velocidad `Vector3.ZERO`;
   - con `jet_velocity = Vector3(0, 0, -8)`, la partícula recibe exactamente esa velocidad;
   - dos corridas con el mismo número de emisiones y snapshot/restore producen la misma
     posición y velocidad después del mismo tick.

## Archivos

**Permitidos únicamente:**

- `core_v2/props/emitters/FireEmitter.gd`
- `core_v2/tests/test_fire_emitter_jet.gd` (nuevo)

**Prohibidos:** cualquier `.tscn`, `project.godot`, `core_v2/systems/gas/**`,
`core_v2/tests/stations/**`, `core_v2/props/pipe/**`, `core_v2/systems/plasma/**` y cualquier
otro archivo.

## Convenciones y aceptación

- Godot 3.6 / GDScript 1.x; no `await`; tipos estáticos; sin `randf`, `randi`, `rand_range`
  ni reloj no determinista.
- No cambiar daño, intervalo de daño, colisiones, lifetime, colores, atlas ni valores por
  defecto existentes.
- Ejecutar:

```bash
./runtest.sh -a ./core_v2/tests/test_fire_emitter_jet.gd
./runtest.sh -a ./core_v2/tests/test_hazard_determinism.gd
```

Cuando termines, publicá el PR contra `feature/FD-255-ship-systems`.
