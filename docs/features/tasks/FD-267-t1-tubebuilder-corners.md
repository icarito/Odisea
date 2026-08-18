# FD-267 t1 — Un solo barrido de tubo para cables y tuberías

## Objetivo

Los cables procedurales del grafo de circuitos salen como **banderas planas amarillas** en vez de
cables. No es solo un problema visual: el collider de esa geometría degenerada se interpone en el
disparo del jugador — un raycast a una fisura parcheable pegaba en `CableVis233_col` en lugar del
parche, o sea que los cables rotos vuelven injugable el puzle que está detrás. Hubo que apagarlos
(`auto_build_cables = false`) para poder seguir.

La causa está en el **barrido del tubo**, no en la ruta: `TubeBuilder.generate_tube_mesh()` barre
un perfil circular a lo largo de una `Curve3D` sin marcos estables, así que en cada esquina dura el
anillo se voltea y el tubo se abre en abanico. Las rutas de cable tienen esquinas de 90° (van del
anchor al piso, cruzan, y suben al otro anchor), así que el defecto se ve siempre.

Ese mismo barrido es el que usan las **tuberías** (`PipeRun` + `PipeRouter`), que routean pegadas
a paredes y techo y por lo tanto también doblan en ángulo recto. O sea: **es un solo defecto que
paga dos veces**. Arreglarlo una vez en la primitiva compartida endereza los cables y de paso le
da codos decentes a las tuberías.

El diseño completo está en `docs/features/FD-267_tube_geometry_convergence.md`. **Léalo antes de
empezar**; este brief es la parte a implementar.

## Contexto del sistema

- El juego es **Godot 3.6, GDScript 1.x**. `yield`, no `await`. Todo el código vive en `core_v2/`.
- El proyecto corre en **GLES2**.
- **Determinismo — contrato duro, ver `AGENTS.md` §5.3.** La geometría generada tiene que ser
  **exactamente reproducible**: misma curva y mismos parámetros ⇒ mismos vértices, bit a bit.
  Nada de `randf()` ni de nada dependiente del framerate. Esto importa especialmente acá: si el
  barrido no es determinista, el replay se rompe.
- Español neutro en comentarios. Sin voseo argentino.
- Los comentarios explican **por qué**, no qué.

### Las piezas

- `core_v2/systems/pipe/TubeBuilder.gd` — la primitiva compartida. Estático:
  - `generate_circle_polygon(radius, sides) -> PoolVector2Array`
  - `generate_tube_mesh(curve: Curve3D, radius, sides, close_caps, u_scale) -> ArrayMesh`
- `core_v2/systems/pipe/PipeRun.gd` — corrida de tubería: routea entre anchors vía `PipeRouter`,
  construye con `TubeBuilder`, aplica el material de flujo, tiene salud y hurtbox. Testeado en
  `core_v2/tests/test_pipe_router.gd`.
- `core_v2/systems/pipe/PipeRouter.gd` — calcula la `Curve3D` entre dos anchors abrazando paredes
  y techo. **No hay que tocarlo**: esta tarea arregla cómo se barre, no por dónde va.
- `core_v2/systems/circuit/CircuitCable.gd` — cable procedural entre nodos del grafo. Hoy tiene su
  propia construcción (`_build_csg()` / `_build_mesh()`), en parte apoyada en `TubeBuilder`.
  Lo instancia `core_v2/systems/circuit/LogicCircuitManager.gd`, que arma la ruta en
  `_generate_catenary()` y llama la API pública del cable.

## Qué implementar

### 1. `TubeBuilder.gd` — marcos de transporte paralelo

- `generate_tube_mesh()` calcula el marco de cada anillo por **transporte paralelo**: cada anillo
  se orienta por rotación mínima respecto del anillo anterior, en vez de derivar un vector "up"
  arbitrario en cada punto. Eso es lo que elimina el volteo en las esquinas.
- El primer anillo necesita un marco inicial elegido de forma **determinista** (no "el eje que
  quede"): elija una regla estable y **coméntela**.
- En esquinas por debajo de un ángulo umbral, insertar **anillos intermedios** (un redondeo chico)
  en lugar de resolver la esquina con un solo anillo compartido: una esquina de 90° con un anillo
  es siempre degenerada. El umbral y el radio del redondeo van como parámetros con default
  razonable, sin romper las llamadas que ya existen.
- **La firma pública no puede cambiar de forma incompatible.** `PipeRun` y `CircuitCable` ya la
  llaman. Parámetros nuevos van al final y con default.

### 2. `CircuitCable.gd` — apoyarse en el barrido común

- Que deje de tener su propia construcción de malla y use el barrido de §1.
- **La API pública no cambia**: `build()`, `path_curve`, `cable_radius`, `cable_sides`,
  `cable_material`, `use_csg`. `LogicCircuitManager` la sigue llamando igual.
- Sacar los `print()` de depuración que dispara en cada `_ready()` y cada `build()`. Con seis
  cables por escena son decenas de líneas por carga.
- El collider del cable tiene que seguir el tubo real. Es lo que hace que deje de interponerse en
  los disparos.

### 3. `PipeRun.gd` — material por corrida

`_get_or_load_material()` cachea el recurso que devuelve `load()` y lo comparte entre corridas.
Como `load()` devuelve **el mismo recurso** para el mismo path, dos corridas en una escena se
pisan los parámetros de flujo entre sí: la última en aplicar manda sobre todas.

Hay que hacer `.duplicate()` del material por corrida. Es exactamente el arreglo que ya se hizo en
`core_v2/props/pipe/PipeCoolantRun.gd` — **mírelo y siga ese criterio**, incluido el comentario que
explica por qué.

### 4. Tests

Nuevo `core_v2/tests/test_tube_builder.gd` (GdUnit3, mismo estilo que los de al lado):

1. Una curva recta produce una malla con la cantidad de vértices esperada y normales coherentes.
2. Una curva con una **esquina de 90°** produce una malla **sin normales invertidas ni triángulos
   degenerados**, y con área acotada — concretamente, que no se abra en abanico: el área de la
   superficie tiene que quedar cerca de la de un tubo del mismo largo y radio, no varias veces
   más grande. Este es el test que captura el bug; escríbalo de forma que **falle con el código de
   hoy** y pase con el arreglo.
3. Determinismo: generar dos veces con la misma curva y los mismos parámetros da **exactamente**
   los mismos vértices.

Correr:

```bash
./runtest.sh -a ./core_v2/tests/test_tube_builder.gd
./runtest.sh -a ./core_v2/tests/test_pipe_router.gd
./runtest.sh -a ./core_v2/tests/test_coolant_lab.gd
```

Las tres en verde. `test_pipe_router.gd` y `test_coolant_lab.gd` **no se tocan**: son la red de
seguridad de que no rompió lo que ya andaba.

## Archivos permitidos

- `core_v2/systems/pipe/TubeBuilder.gd`
- `core_v2/systems/pipe/PipeRun.gd`
- `core_v2/systems/circuit/CircuitCable.gd`
- `core_v2/tests/test_tube_builder.gd` (nuevo)

## Archivos prohibidos

- `core_v2/systems/pipe/PipeRouter.gd` y
  `core_v2/systems/circuit/LogicCircuitManager.gd` — la **ruta** queda como está; esta tarea
  arregla el **barrido**. Si cree que la ruta también está mal, dígalo en el PR; no la cambie.
- `core_v2/scenes/CoolantLab.tscn` — escena ya verificada. Si su arreglo permite volver a prender
  `auto_build_cables`, **dígalo en el PR**; no lo edite usted.
- `core_v2/tests/test_pipe_router.gd`, `core_v2/tests/test_coolant_lab.gd`
- Cualquier escena de nivel (`core_v2/levels/**`), en especial `Dome_Intro.tscn`
- `core_v2/systems/cryo/**`, `core_v2/props/pipe/CoolantTank.gd`,
  `core_v2/props/pipe/PipeCoolantRun.gd`, `core_v2/scenes/CoolantLab.gd` — son de otra tarea en
  paralelo (FD-266). Tocarlos genera conflicto. `PipeCoolantRun.gd` léalo como referencia, pero no
  lo modifique.

## Qué NO hacer

- No cambiar la firma pública de `TubeBuilder` ni de `CircuitCable` de forma incompatible.
- No reescribir `PipeRouter` ni el ruteo de cables del manager.
- No meter aleatoriedad ni nada no reproducible en la generación de geometría.
- No agregar dependencias ni addons.
- No convertir el laboratorio a tubería procedural: es otra tarea, más adelante.

## Al terminar

**Publique el Pull Request** contra la rama de trabajo indicada, con un resumen de qué cambió en
el barrido y qué prueba el test de la esquina. Si el arreglo habilita volver a prender
`auto_build_cables` en el laboratorio, dígalo. Si algo del brief resultó imposible o ambiguo,
dígalo en el PR en vez de adivinar.
