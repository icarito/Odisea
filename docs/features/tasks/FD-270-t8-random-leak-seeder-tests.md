# FD-270 T8 (JM4): Tests GdUnit3 de `RandomLeakSeeder`

## Objetivo

Escribir los tests GdUnit3 de `RandomLeakSeeder` (`core_v2/systems/cryo/RandomLeakSeeder.gd`).
Esta tarea se despacha en paralelo con la que construye ese script (mismo contrato, sesión
distinta) — puede que el archivo no exista todavía cuando arranques, o que exista con pequeñas
diferencias respecto al contrato de abajo. Si el archivo ya existe y difiere del contrato descrito
acá, **usá lo que el archivo real expone**, no lo que describe este brief — el contrato es la
intención, el código ya escrito manda.

## Contexto del sistema

Motor Godot 3.6 / GDScript 1.x, tests con GdUnit3. Mirá `core_v2/tests/test_coolant_puzzle_loop.gd`
o `core_v2/tests/test_room_environment.gd` para el estilo exacto de este repo: clase base que
extienden los tests, cómo se instancian nodos de prueba (`auto_free(...)`), convención de nombres
`test_*`, cómo se arma un árbol de escena mínimo en el test.

## Contrato esperado de `RandomLeakSeeder` (si el archivo ya existe, verificalo contra el real)

```gdscript
extends Node
class_name RandomLeakSeeder

export(int) var seed := 42
export(int) var leak_count := 2
export(Array, NodePath) var candidate_leak_paths := []

func get_snapshot() -> Dictionary  # {"seed": int, "active_leak_paths": Array de String}
func restore_snapshot(data: Dictionary) -> void
```

El sorteo (shuffle Fisher-Yates con `RandomNumberGenerator` propio sembrado con `seed`) corre en
`_ready()` y llama `trigger_leak()` sobre las `CoolantLeak` elegidas. `restore_snapshot()` no
vuelve a correr el RNG: aplica directo la lista de rutas que trae el snapshot.

## Tests a escribir

En `core_v2/tests/test_random_leak_seeder.gd`:

1. **`test_random_leak_seeder_deterministic`**: crear un árbol de escena de prueba con varios nodos
   `Spatial` (con script `CoolantLeak.gd` si hace falta que `trigger_leak()` no falle al llamarse,
   o simples `Spatial` si el seeder tolera nodos sin ese método — revisá el código real para saber
   qué necesita) como candidatos, con nombres fijos. Instanciar **dos** `RandomLeakSeeder`
   distintos, ambos con el mismo `seed` y la misma `candidate_leak_paths` (mismos `NodePath`
   relativos, mismo árbol de escena o dos árboles idénticos). Verificar que
   `seeder_a.get_snapshot()["active_leak_paths"]` es exactamente igual (mismo contenido, mismo
   orden si el snapshot preserva orden) a `seeder_b.get_snapshot()["active_leak_paths"]`.

2. **`test_random_leak_seeder_snapshot_roundtrip`**: instanciar un `RandomLeakSeeder` con `seed=1`,
   dejar que sortee, tomar su `get_snapshot()`. Instanciar un segundo `RandomLeakSeeder` con
   `seed=999` (deliberadamente distinto) y la misma `candidate_leak_paths`, dejar que sortee (va a
   dar un resultado distinto al primero). Llamar `seeder_b.restore_snapshot(snapshot_de_a)`.
   Verificar que `seeder_b.get_snapshot()["active_leak_paths"]` ahora es igual al snapshot original
   de `a`, no al que hubiera dado su propio seed 999.

Usá `auto_free()` para los nodos de prueba (evitar leaks de memoria entre tests, mismo patrón que
el resto de `core_v2/tests/`).

## Archivos permitidos

- `core_v2/tests/test_random_leak_seeder.gd` (nuevo)

## Archivos prohibidos

- `core_v2/systems/cryo/RandomLeakSeeder.gd` (no lo edites, aunque encuentres algo que te parezca
  un bug — si el contrato no calza con lo que necesitás testear, escribí el test contra el
  comportamiento real del archivo y dejá una nota en el PR explicando la discrepancia, no lo
  arregles vos)
- Cualquier `.tscn`
- `project.godot`
- Cualquier archivo fuera de `core_v2/tests/test_random_leak_seeder.gd`

## Reglas

- Godot 3.6 / GDScript 1.x, estilo GdUnit3 del repo. `yield`, nunca `await`.
- Si `core_v2/systems/cryo/RandomLeakSeeder.gd` todavía no existe cuando arrancás, esperá/reintentá
  o escribí los tests igual contra el contrato descrito arriba dejándolos listos — si al momento de
  correr `runtest.sh` el archivo no existe todavía, documentalo en el PR en vez de fallar en
  silencio.

## Criterio de aceptación

`./runtest.sh -a core_v2/tests/test_random_leak_seeder.gd` corre y ambos tests pasan (una vez que
`RandomLeakSeeder.gd` exista en el repo — si tu sesión corre antes de que esté mergeado, dejalo
documentado en el PR y no bloquees la entrega por eso).

## Qué NO hacer

- No edites `RandomLeakSeeder.gd`.
- No inventes tests adicionales fuera de los dos pedidos (YAGNI — si ves un caso interesante
  extra, mencionalo en el PR en vez de agregarlo sin que se pida).

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
