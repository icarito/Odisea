# FD-270 T5 (JM1): `RandomLeakSeeder`

## Objetivo

Crear `core_v2/systems/cryo/RandomLeakSeeder.gd`: un nodo que, al arrancar la partida, sortea de
forma determinista cuáles de varias fugas de refrigerante ya colocadas en la escena arrancan
activas. La posición/geometría de las fugas es de autoría (fija, puesta a mano en la escena) —
este nodo no crea ni mueve nada, solo decide **cuáles** de las candidatas empiezan a gotear.

## Contexto del sistema

Motor Godot 3.6 / GDScript 1.x (`extends`/`class_name`, `export()` con paréntesis, `yield` nunca
`await`). Todo el código de sistemas vive bajo `core_v2/systems/`.

El juego tiene un puzle de refrigerante con varias fisuras (`CoolantLeak`, script en
`core_v2/systems/cryo/CoolantLeak.gd`, ya existe, no lo edites). Cada `CoolantLeak` es un nodo
`Spatial` con `export(bool) var starts_leaking` que, si es `true`, dispara `trigger_leak()` en su
propio `_ready()`. Hoy todas las fugas de una escena están fijas en autoría (siempre las mismas
activas). El objetivo de este sistema es sortear, con una semilla fija, cuáles 2-3 fugas de un
conjunto más grande de candidatas arrancan activas cada partida — reproducible (mismo seed →
mismo resultado) porque el juego tiene un sistema de replay determinista que no tolera
aleatoriedad sin seed (`randf()`/`randomize()` desnudos están prohibidos en lógica de gameplay).

**Importante sobre el orden de `_ready()`:** en Godot, el orden de `_ready()` entre nodos hermanos
sigue el orden del árbol de escena, no está garantizado que este seeder corra antes que las
`CoolantLeak` que va a activar. Por eso el seeder **no** debe depender de escribir la propiedad
`starts_leaking` de una `CoolantLeak` (se leería demasiado tarde). En vez de eso, para cada fuga
elegida, el seeder debe llamar directamente `leak.trigger_leak()` en su propio `_ready()` — ese
método ya existe en `CoolantLeak.gd` y es seguro de llamar en cualquier momento después de que el
nodo destino exista (revisa su código para confirmar que es idempotente/seguro, no lo edites).

## Contrato exacto

```gdscript
extends Node
class_name RandomLeakSeeder

export(int) var seed := 42
export(int) var leak_count := 2
export(Array, NodePath) var candidate_leak_paths := []
```

- `_ready()`:
  1. Agregar el nodo al grupo `"replay_sync"` (`add_to_group("replay_sync")`) — es el contrato de
     determinismo del proyecto para todo lo que participa en el snapshot/replay.
  2. Si `_active_leak_paths` ya fue restaurado por `restore_snapshot()` (ver abajo) antes de que
     `_ready()` corra, usar esa lista tal cual y no volver a sortear. Si no, sortear.
  3. Sorteo: crear un `RandomNumberGenerator` **propio** de esta instancia (no usar el RNG global
     `randi()`/`randf()` del motor), sembrarlo con `seed` (`rng.seed = seed`), y hacer un shuffle
     Fisher-Yates de una copia de `candidate_leak_paths` usando `rng.randi_range(0, i)` en cada
     paso. Tomar los primeros `min(leak_count, candidate_leak_paths.size())` elementos del array
     ya mezclado como `_active_leak_paths`.
  4. Para cada `NodePath` en `_active_leak_paths`, resolver el nodo con `get_node_or_null()` (desde
     este nodo primero, y si no resuelve, desde el padre — mismo patrón de fallback que ya usa
     `CoolantFlowAdapter._get_target_node()` en `core_v2/systems/cryo/CoolantFlowAdapter.gd`, podés
     copiarlo o adaptarlo) y, si no es `null`, llamar `leak.trigger_leak()`.

- `get_snapshot() -> Dictionary`: devuelve `{"seed": seed, "active_leak_paths": _active_leak_paths}`
  donde `active_leak_paths` es un array de `String` (convertí cada `NodePath` con `str()` para que
  sea serializable) — son las rutas **ya sorteadas**, no un valor recalculable.

- `restore_snapshot(data: Dictionary) -> void`: si `data` tiene `"active_leak_paths"`, guarda esa
  lista (convertida de vuelta a `NodePath` si hace falta) en `_active_leak_paths` **sin volver a
  correr el RNG**. Esto es clave: el replay debe reproducir el mismo resultado del sorteo aunque
  cambie el orden de `_ready()`, y no depende de que `candidate_leak_paths` no haya cambiado entre
  versiones de la escena.

- Variable interna: `var _active_leak_paths: Array = []`.

## Archivos permitidos

- `core_v2/systems/cryo/RandomLeakSeeder.gd` (nuevo)

## Archivos prohibidos

- Cualquier `.tscn` (no instancies este nodo en ninguna escena, eso lo hacemos nosotros a mano)
- `project.godot`
- `core_v2/systems/cryo/CoolantLeak.gd` (no lo edites, solo lo llamás)
- `core_v2/systems/cryo/CoolantFlowAdapter.gd` (solo mirá `_get_target_node()` como referencia de
  patrón, no lo edites)
- Cualquier archivo fuera del listado en "Archivos permitidos"

## Reglas

- Godot 3.6 / GDScript 1.x: `export(int)`, `export(Array, NodePath)`. `yield`, nunca `await`.
- Sin dependencias nuevas, sin autoloads nuevos.
- No uses `randf()`/`randi()`/`randomize()` globales del motor — el RNG tiene que ser una instancia
  propia (`RandomNumberGenerator.new()`) sembrada explícitamente, para que dos sesiones con el
  mismo seed den el mismo resultado sin importar qué más haya consumido el RNG global antes.

## Criterio de aceptación

Un test GdUnit3 en `core_v2/tests/test_random_leak_seeder.gd` (mirá otros tests en `core_v2/tests/`
para copiar el estilo — por ejemplo `core_v2/tests/test_coolant_puzzle_loop.gd` o
`core_v2/tests/test_room_environment.gd`) que cubra:

- `test_random_leak_seeder_deterministic`: crear dos instancias de `RandomLeakSeeder` con el mismo
  `seed` y la misma `candidate_leak_paths` (podés usar `NodePath`s de prueba, no hace falta que
  resuelvan a nodos reales para verificar el sorteo — si tu diseño necesita nodos reales para que
  `_ready()` corra el sorteo, instanciá nodos `Spatial` dummy con esos nombres bajo un padre común
  en el test). Verificar que `get_snapshot()["active_leak_paths"]` es idéntico en ambas instancias.
- `test_random_leak_seeder_snapshot_roundtrip`: crear una instancia, tomar su `get_snapshot()`,
  crear una segunda instancia con un seed **distinto**, llamarle `restore_snapshot()` con el
  snapshot de la primera, y verificar que su `get_snapshot()["active_leak_paths"]` ahora coincide
  con el de la primera (no con lo que hubiera sorteado su propio seed).

Correr `./runtest.sh -a core_v2/tests/test_random_leak_seeder.gd` y que pase.

## Qué NO hacer

- No instancies este nodo en ninguna escena — eso lo hacemos nosotros a mano después, calibrando
  qué `CoolantLeak` concretas van como candidatas en cada circuito del domo.
- No edites `CoolantLeak.gd` ni le agregues métodos nuevos — usá lo que ya expone (`trigger_leak()`).
- No uses el RNG global del motor (`randf`, `randi`, `randomize`) — semilla propia por instancia.
- No inventes campos adicionales en el contrato de exports de arriba.

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
