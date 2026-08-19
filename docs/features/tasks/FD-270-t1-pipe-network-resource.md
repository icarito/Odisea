# FD-270 T1 (J1): `PipeNetworkResource`

## Objetivo

Crear `core_v2/systems/pipe/PipeNetworkResource.gd`: un `Resource` que guarda la topología
ordenada de una red de tuberías de refrigerante, como un árbol dirigido tanque → válvulas →
fisura → sumidero, sin ciclos ni bifurcaciones. Este recurso es puro dato + validación; el
cálculo de caudal (que lo consume) es una tarea aparte.

## Contexto del sistema

Este es el motor Godot 3.6 / GDScript 1.x del juego Odisea (`extends`/`class_name`, `export()`
con paréntesis, `yield` — nunca `await`, que no existe en esta versión). Todo el código de
sistemas vive bajo `core_v2/systems/`.

El juego tiene un puzle de refrigerante (criocoolant) con dos ramas (oeste/este), cada una:
tanque → válvula 1 → válvula 2 → fisura → sumidero. El objetivo de diseño (fuera del alcance de
esta tarea, para contexto) es que el caudal visual se corte exactamente en el tramo donde está
la avería, y los tramos aguas arriba de una válvula cerrada sigan corriendo. Para eso hace falta
saber, para cada tramo del caño, cuál válvula y cuál fisura están en su entrada — hoy esa
información no existe en ningún lado como dato estructurado (son listas planas sin orden).

Esta tarea es solo el recurso de datos. No lo conectes a nada del `_physics_process` ni al
adapter de flujo — eso es una tarea posterior (T2) que ya tiene su propio brief y depende de esta.

## Contrato exacto

```gdscript
extends Resource
class_name PipeNetworkResource

# branches: Dictionary { branch_id (String) -> BranchData }
# BranchData (Dictionary): {
#   "tank": NodePath,
#   "segments": Array of SegmentData   # EN ORDEN, del tanque al sumidero
# }
# SegmentData (Dictionary): {
#   "pipe_run": NodePath,   # el PipeCoolantRun de este tramo
#   "valve": NodePath,      # opcional (puede ser NodePath vacío): válvula EN LA ENTRADA de este tramo
#   "leak": NodePath,       # opcional (puede ser NodePath vacío): fisura EN LA ENTRADA de este tramo
#   "flow_dir": Vector3     # dirección de este tramo, en coordenadas de mundo
# }
export(Dictionary) var branches := {}
```

Semántica de `valve` y `leak`: van **en la entrada** del tramo, no en la salida. Una válvula
cerrada en el tramo `i` corta el caudal de `i` y de todo lo que sigue (`i+1`, `i+2`, ...); el
tramo `i-1` no se ve afectado. Una fisura en la entrada del tramo `i` reduce el caudal desde `i`
en adelante (la reducción exacta la calcula otra tarea; acá solo hace falta poder recorrer los
datos en orden y saber en qué índice está cada válvula/fisura).

## `validate() -> Dictionary`

Debe devolver algo como `{"ok": bool, "errors": Array de String}` (elegí vos el shape exacto,
pero que sea fácil de testear: si `ok` es `false`, `errors` tiene al menos un mensaje legible por
cada problema encontrado). Tiene que rechazar, para cada rama de `branches`:

1. Un `NodePath` que no resuelve — esto solo se puede chequear si el recurso está en un árbol de
   escena con acceso a `get_node_or_null`, así que `validate()` debe aceptar un `Node` de
   contexto (`func validate(context: Node) -> Dictionary`) desde el que resolver los paths.
2. Una rama sin `tank` (NodePath vacío o nulo).
3. Una rama con `segments` vacío.
4. Cualquier `pipe_run` (por su NodePath, comparado como String o resuelto y comparado por
   instancia) que aparezca en más de un tramo, en la misma rama o en ramas distintas — sería un
   caño con dos caudales a la vez, y es justamente el error que este recurso existe para prevenir.

No hace falta que `validate()` chequee que los `NodePath` resuelven a nodos del tipo correcto
(`PipeCoolantRun`, válvula, fisura) — con que no sean `null` alcanza para esta tarea.

## Archivos permitidos

- `core_v2/systems/pipe/PipeNetworkResource.gd` (nuevo)
- Un test GdUnit3 en `core_v2/tests/` (ver criterio de aceptación) — mirá `core_v2/tests/` para
  copiar el estilo de los tests existentes (extend de la clase base de test que uses en el repo,
  convención de nombres `test_*`)

## Archivos prohibidos

- Cualquier `.tscn` (escenas)
- `project.godot`
- `core_v2/systems/cryo/**` (el adapter que va a consumir este recurso es tarea aparte)
- Cualquier archivo fuera de los dos listados arriba

## Reglas

- Godot 3.6 / GDScript 1.x: `export(Dictionary)`, `export(NodePath)`, sin tipado estático de
  parámetros de función más allá de lo que ya uses de ejemplo en el repo. `yield`, nunca `await`.
- Sin dependencias nuevas, sin autoloads nuevos.
- No hace falta lógica de caudal ni de shader acá — es solo el recurso de datos y su validación.

## Criterio de aceptación

Un test GdUnit3 (`core_v2/tests/test_pipe_network_resource.gd` o el nombre que uses siguiendo la
convención del directorio) que cubra:

- Rama válida con 3-4 tramos pasa `validate()` sin errores.
- Rama sin `tank` falla.
- Rama con `segments` vacío falla.
- Un `pipe_run` repetido en dos tramos falla.
- Un `NodePath` que no resuelve (contra un `Node` de contexto de prueba) falla.

Correr `./runtest.sh -a core_v2/tests/test_pipe_network_resource.gd` (o el path que uses) y que
pase.

## Qué NO hacer

- No implementes el cálculo de caudal (`compute_flow`, barrido O(n)) — es la tarea T2, aparte.
- No toques `CoolantFlowAdapter.gd` ni ningún otro sistema existente.
- No instancies este recurso en ninguna escena — eso lo hacemos nosotros a mano después,
  calibrando la geometría real del laboratorio.
- No inventes campos adicionales en `SegmentData` que no estén en el contrato de arriba.

---

Cuando termines, publicá el PR contra la rama `feature/FD-270-pipe-network-flow`.
