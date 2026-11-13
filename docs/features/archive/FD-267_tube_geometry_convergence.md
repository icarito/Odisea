# FD-267: Un solo barrido de tubo para cables y tuberías

**Status:** Open (parcial — el defecto principal sigue vivo)
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-08-17
**Parent:** FD-264 / FD-265

## Problem

Hay **tres** sistemas que generan tubos y no se hablan del todo:

| Sistema | Qué hace | Estado |
|---|---|---|
| `core_v2/systems/pipe/TubeBuilder.gd` | Barre un círculo a lo largo de una `Curve3D` | Primitiva compartida |
| `core_v2/systems/pipe/PipeRun.gd` + `PipeRouter.gd` | Routea entre anchors y construye la tubería, con material de flujo, salud y hurtbox | Existe, testeado (`test_pipe_router.gd`), **casi sin usar** |
| `core_v2/systems/circuit/CircuitCable.gd` | Cable procedural entre nodos del grafo OCLS | Tiene su propia ruta y su propio armado |

El resultado se ve en `CoolantLab.tscn`: con `auto_build_cables = true`, los cables salen como
**banderas planas amarillas** entre los nodos en vez de cables. Y no es solo feo: el collider de
esa geometría degenerada **se interpone en el disparo de gloo** — un raycast a la fisura pegaba en
`CableVis233_col` en lugar del parche, o sea que los cables rotos volvían el puzle injugable. En
FD-265 hubo que apagarlos (`auto_build_cables = false`) para poder seguir.

La causa está en el barrido: `LogicCircuitManager._generate_catenary()` arma la ruta con esquinas
de 90° (anchor → piso → cruza → piso → anchor) y `TubeBuilder.generate_tube_mesh()` barre el
perfil sin marcos estables, así que en cada esquina dura el anillo se voltea y el tubo se abre en
abanico. Es el mismo barrido que usan las tuberías, así que **el defecto es de los dos**.

Además `PipeRun._get_or_load_material()` cachea el recurso de `load()` por path y lo comparte
entre corridas — el mismo defecto que ya se corrigió en `PipeCoolantRun.gd` (dos corridas en una
escena se pisan los parámetros de flujo entre sí; la última en aplicar manda sobre todas).

## Solution

Arreglar el barrido **una sola vez**, en la primitiva que ya comparten, y hacer que el cable sea
una configuración de ese barrido en vez de una copia.

### 1. Marcos de transporte paralelo en `TubeBuilder`

`generate_tube_mesh()` calcula el marco de cada anillo con transporte paralelo (rotación mínima
respecto del anillo anterior) en vez de derivar un "up" arbitrario por punto. Eso elimina el
volteo en las esquinas duras, que es lo que produce las banderas.

En esquinas por debajo de un ángulo umbral, insertar anillos intermedios (un pequeño redondeo)
en lugar de un solo anillo compartido: una esquina de 90° con un anillo es siempre degenerada.

Beneficio doble: los cables dejan de romperse **y** las tuberías ganan codos decentes, que es
justo lo que `PipeRouter` necesita para routear pegado a paredes y techo.

### 2. `CircuitCable` sobre el barrido común

`CircuitCable` deja de tener su propia construcción de malla y pasa a apoyarse en la misma ruta
(`TubeBuilder` + el redondeo de §1), quedando como configuración: radio, lados, material, y el
colgado del cable. La API pública (`build()`, `path_curve`, `cable_radius`, `cable_sides`,
`cable_material`) **no cambia**: `LogicCircuitManager` la sigue llamando igual.

Sacar de paso los `print()` de depuración que el script dispara en cada `_ready()` y cada
`build()` — con seis cables por escena son decenas de líneas por carga.

### 3. Material por corrida en `PipeRun`

Mismo arreglo que ya se hizo en `PipeCoolantRun`: `.duplicate()` del material por corrida en vez
de compartir el recurso de `load()`.

## Considered Options

- **A. Solo arreglar la geometría de esquinas** — los cables dejan de romperse, pero quedan dos
  caminos separados y la próxima diferencia entre cable y tubería se vuelve a pagar dos veces.
- **B. Convergir en `TubeBuilder` + `PipeRun`** — un barrido, dos usos. **Seleccionada.**
- **C. Además, pasar `CoolantLab` a tubería procedural** — probaría el sistema en un caso real,
  pero mueve el piso del laboratorio recién verificado. Se deja para después.

## Files to Modify

- `core_v2/systems/pipe/TubeBuilder.gd` — transporte paralelo + redondeo de esquinas (§1)
- `core_v2/systems/circuit/CircuitCable.gd` — apoyarse en el barrido común, sacar prints (§2)
- `core_v2/systems/pipe/PipeRun.gd` — material por corrida (§3)
- `core_v2/tests/test_tube_builder.gd` (nuevo) — geometría del barrido

**Fuera de alcance:** `LogicCircuitManager._generate_catenary()` (la *ruta* puede seguir igual;
esta tarea arregla cómo se barre, no por dónde va), `CoolantLab.tscn`, `Dome_Intro.tscn`, y
cualquier escena de nivel.

## Plan de tareas

| Tarea | Qué | Ejecutor | Sesión | Brief |
|---|---|---|---|---|
| t1 | Barrido común + convergencia de cable | Jules | `537927738519409501` | `docs/features/tasks/FD-267-t1-tubebuilder-corners.md` |

Calibración de valores exportados y cableado en `CoolantLab.tscn`: Sebastián, después del merge.

## Estado tras la primera pasada (2026-08-17)

Entregado y mergeado: fillet de esquinas y marcos estables en `TubeBuilder`, `CircuitCable`
apoyado en el barrido comun y sin sus `print()` por carga, y material por corrida en `PipeRun`.

**No resuelto — el objetivo principal.** Verificado en vivo con `auto_build_cables = true`:
los cables **siguen saliendo como banderas planas amarillas** y su collider **sigue
interponiendose en el disparo de gloo** (el raycast a la fisura pega en `CableVis*_col`).
O sea que la causa **no eran las esquinas**. Descartado tambien que sea la rama CSG:
`use_csg` es `false`, asi que los cables pasan por el `TubeBuilder` que se arreglo.

`test_tube_builder.gd` **no discrimina**: pasa igual con el `TubeBuilder` anterior, o sea que
no es red de seguridad de nada. Cualquier proxima pasada tiene que empezar por un test que
falle con el codigo de hoy.

Proxima hipotesis a investigar: la *ruta* que arma `LogicCircuitManager._generate_catenary()`
(puntos duplicados o colineales, o el tramo anchor->piso de largo cero cuando el anchor ya esta
en el piso), que quedo explicitamente fuera de alcance en esta pasada.

## Verification

1. `test_tube_builder.gd`: una curva con una esquina de 90° produce una malla sin normales
   invertidas ni triángulos degenerados, y con área acotada (no "abanico").
2. `test_pipe_router.gd` sigue verde.
3. `CoolantLab.tscn` con `auto_build_cables = true` muestra cables que leen como cables.
4. Con los cables prendidos, un raycast desde el jugador a cada `*_Patch` sigue pegando en el
   `StaticBody` del parche y no en el collider del cable
   (`test_coolant_lab.test_scene_wiring_supports_shader_and_gloo`).
5. Dos `PipeRun` en una escena con distintos `flow_speed` no se pisan los parámetros.
