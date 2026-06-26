# FD-052: Acto 0 — Maze de Ductos Radial (MST Polar)

**Status:** Draft
**Priority:** P1
**Effort:** Medium
**Created:** 2026-06-26
**Depends on:** ScaffoldMSTGenerator (FD-050), Pipe props (FD-044), Tube Connector (FD-025)

## 1. Visión General

Prólogo jugable del Acto 0: Elías atraviesa un laberinto de ductos dentro de un
tanque cilíndrico de ~30m de diámetro. La secuencia es cinética, claustrofóbica,
y termina en una esclusa con corte a negro que empalma con el despertar
criogénico del Acto I.

A diferencia del doc `Acto_0_Cold_Open.md` (runner lineal 2.5D), este diseño
usa **generación procedural MST proyectada a coordenadas polares** para crear un
maze volumétrico de ductos interconectados dentro del volumen cilíndrico.

**No es un árbol de decisiones.** Es un solo espacio tridimensional lleno de
tubos entrecruzados. El jugador navega, no elige ramas. La presión viene de
colapsos, fugas y compuertas que se cierran — no de bifurcaciones con timer.

## 2. Proyección Polar del MST Generator

### 2.1 Principio

El `ScaffoldMSTGenerator` opera sobre un grid 2D abstracto (X, Y) con altura
independiente (Z). El algoritmo no cambia — solo se reinterpreta la geometría
al instanciar los tiles:

```
Grid X → Ángulo θ  (circunferencial)
Grid Y → Radio r   (radial)
Height → Altura z  (vertical)
```

### 2.2 Conversión de Conexiones

**Importante — el generador es _per-cell_, no _per-edge_.** El
`ScaffoldMSTGenerator` no emite "un tubo entre dos celdas". Emite **un tile por
celda**, clasificado por la firma de sus conexiones (ver
`_select_variant`, [ScaffoldMSTGenerator.gd:600](../../core_v2/systems/ScaffoldMSTGenerator.gd#L600)).
El spawner elige el tile por `variant.id` y usa `variant.rotation` para
orientarlo en el espacio polar. No hay que inventar tiles "por dirección".

Cada dirección de conexión se interpreta geométricamente así:

| Dirección MST | Significado físico | Geometría del brazo |
|---|---|---|
| EAST/WEST | circunferencial | arco de circunferencia a radio constante (tangente) |
| NORTH/SOUTH | radial | tramo recto en dirección radial |
| Height delta | desnivel | el brazo recto se **inclina** (no es un tubo vertical aparte) |

El desnivel **nunca viaja solo**: el MST siempre lo monta sobre un recto pasante
(la variante `S`, dos puertos opuestos a distinta altura — ver normalización en
[ScaffoldMSTGenerator.gd:627](../../core_v2/systems/ScaffoldMSTGenerator.gd#L627)).
Por eso en este maze no existen tubos verticales puros: hay **tubos inclinados**.

### 2.3 Parámetros del Grid para el Cilindro de 30m

```
Volumen objetivo:  cilindro diámetro 30m × altura 15m
Radio exterior:   14m
Radio interior:    2m (hueco central, puede ser eje de la nave o vacío)
Radial span:      12m (14m - 2m)

grid_width:       12 sectores  → 30° por sector
grid_depth:        6 anillos   → 2m por paso radial
cell_size:         N/A (la distancia radial se calcula por anillo)
max_height_steps:  6           → 0 a 12m de altura (paso 2m)
min_height_steps:  1

HEIGHT_STEP:       2.0m        (se mantiene el default del generador)
```

Con estos parámetros, cada celda del grid ocupa un arco de 30° y un anillo de
2m de espesor radial. Las cápsulas (nodos) ocupan una celda. Los tubos conectan
celdas adyacentes.

### 2.4 Fórmulas de Instanciación

> [!IMPORTANT] Coordenadas Odisea
> El juego usa **-Z como FORWARD** y **+Z como BACK**. Las piezas de ducto
> deben respetar eso: en una pieza recta sin rotación, el eje navegable local es
> `-Z`, y el lado `+Z` queda hacia la cámara/espalda del jugador. La proyección
> polar no puede corregir esto con flips arbitrarios porque rompería la lectura
> cámara-personaje y los ports de `variant.rotation`.

```gdscript
# Constantes del layout
const INNER_RADIUS := 2.0
const RING_STEP := 2.0
const SECTORS := 12
const ANGLE_STEP := 360.0 / SECTORS

func grid_to_world(grid_x: int, grid_y: int, height: float) -> Transform:
    var angle_deg := float(grid_x) * ANGLE_STEP
    var angle_rad := deg2rad(angle_deg)
    var radius := INNER_RADIUS + float(grid_y + 0.5) * RING_STEP

    var world_x := radius * cos(angle_rad)
    var world_z := radius * sin(angle_rad)

    var pos := Vector3(world_x, height, world_z)

    # Base local:
    #   X  -> tangente positiva (circunferencial)
    #   Y  -> arriba
    #   Z  -> radial hacia afuera
    #
    # Convención de pieza:
    #   -Z local es "forward" navegable para ductos rectos.
    #   +Z local es back/cámara, consistente con Odisea.
    #
    # variant.rotation se aplica alrededor de Y local después de construir este
    # basis. No se debe invertir Z para "arreglar" visualmente una pieza: si un
    # port queda mal, el asset está orientado incorrectamente.
    var tangent := Vector3(-sin(angle_rad), 0, cos(angle_rad))
    var radial := Vector3(cos(angle_rad), 0, sin(angle_rad))
    var up := Vector3.UP

    var basis := Basis(tangent, up, radial)
    return Transform(basis, pos)
```

## 3. Inventario de Tiles

### 3.1 Tiles Existentes (Decorativos — Diámetro 0.4m)

Estos props existen en `core_v2/props/pipe/`. Son de diámetro 0.4m (radio
0.2m), demasiado pequeños para que Elías los atraviese. Se reutilizan como
**tuberías decorativas no navegables** en las paredes de las cápsulas y zonas
de contenido (gas/agua/aire).

| Tile | Archivo | Función decorativa |
|---|---|---|
| PipeSection | `PipeSection.tscn` | Tramo recto horizontal (radio 0.2, largo 2.0) |
| PipeCorner | `PipeCorner.tscn` | Codo 90° horizontal, 2 brazos de 1m |
| PipeTee | `PipeTee.tscn` | Intersección T, 3 brazos de 1m |
| PipeValve | `PipeValve.tscn` + `.gd` | Válvula interactiva (extiende InteractableBaseV2) |

### 3.2 Tiles Navegables Nuevos (Diámetro 4m)

Tubos por los que Elías puede caminar/correr/arrastrarse. Diámetro interno 4m
(radio 2m), paredes de 0.1m de espesor. Todos heredan de `Spatial`, colisión
`StaticBody` + `ConcaveShape`.

**El inventario navegable se deriva directamente de la firma de conexiones que
emite el generador** — un tile por cada variante posible, no por dirección de
arista. Nombramos los navegables `Duct*` (4m) para no colisionar con los
decorativos `Pipe*` (0.4m) de `core_v2/props/pipe/`.

| `variant.id` | conexiones | Tile navegable | Geometría en polar |
|---|---|---|---|
| `E` | 1 | **DuctEndCap** | tapa ciega + stub corto de 1m (×4 rotaciones) |
| `W` rot 0/180 | 2 opuestas radiales | **DuctRadial** | cilindro hueco recto radial, largo = RING_STEP (2m) |
| `W` rot 90/270 | 2 opuestas circunf. | **DuctArc** | segmento de toro, `major_radius` = radio del anillo, `minor_radius` 2.0, `arc` 30° |
| `C` | 2 adyacentes | **DuctElbow** | codo que une un brazo recto-radial con un brazo arco-tangente (×4) |
| `T` | 3 | **DuctTee** | te; el brazo circunferencial curva, los radiales rectos (×4) |
| `X` | 4 | **DuctCross** | cruz: esfera central (radio 2.5) + 4 brazos a N/S radiales y E/W tangentes |
| `S` | 2 opuestas + Δh | **DuctIncline** | el recto pero inclinado según `port_heights` (radial o circunferencial) |

7 tiles cubren **toda** la salida del generador.

#### Contrato común `DuctPort`

Todas las piezas navegables implementan el mismo contrato geométrico:

- Diámetro interno: **4.0m** (radio navegable 2.0m).
- Espesor visible de pared: **0.1m** mínimo.
- Cada port abierto está centrado en el borde de celda correspondiente y a
  altura `base_height + variant.port_heights[dir]`.
- El anillo del port debe tener radio 2.0m y una brida visible compatible con
  las puertas/iris del `AirlockChamber`.
- Las piezas rectas se authorizan con eje navegable local `-Z`. El spawner rota
  por `variant.rotation`; no recalcula firmas ni remapea conexiones.
- Las colisiones del corredor deben permitir correr/cámara OTS sin engancharse
  en costillas, bridas o conduits decorativos.

Notas geométricas clave:

- **`DuctArc` debe ser mesh procedural.** El `major_radius` cambia con el anillo
  (`grid_y`), así que no sirve una escena estática por anillo — ver §6.2.
- **`DuctElbow`/`DuctTee`/`DuctCross` no son codos/uniones planares simétricos.**
  En el espacio polar, un brazo radial es recto y un brazo circunferencial es un
  arco tangente; la unión tiene que mezclar recto→arco. Esto vale para todas las
  variantes con al menos un brazo E/W.
- **`DuctIncline` reemplaza al "PipeVertical" del borrador.** No hay tubo
  vertical puro: el desnivel siempre cabalga sobre un recto (la variante `S`). El
  `rotation` y `port_heights` del tile dicen el eje y la pendiente.
- **Junctions = hub + brazos.** `DuctElbow`, `DuctTee` y `DuctCross` se modelan
  como un hub central compacto más segmentos de brazo que llegan a los ports.
  No usar cilindros completos solapados: generan z-fighting, colisión pesada y
  exceso de superficies.

#### Lenguaje visual y materiales

La referencia visual directa es `core_v2/props/doors/AirlockChamber.tscn`:
cáscara oscura horneada, costillas estructurales, conduits laterales, piso de
rejilla y strips de luz de emergencia. Los ductos deben leerse como piezas del
mismo sistema industrial, no como tubos genéricos brillantes.

Materiales compartidos recomendados:

| Material | Uso | Notas |
|---|---|---|
| `DuctHull` | paneles exteriores/interiores | metal oscuro paneado, roughness alto, emisión solo en seams |
| `DuctFloorGrate` | banda caminable inferior | patrón de rejilla/diamond plate similar a `airlock_floor.shader` |
| `DuctLightStrip` | strips cian/naranja | emisión acotada; no iluminar toda la pared |
| `DuctConduit` | cañerías decorativas | metal gris, compatible con `PipeMetal.tres` |
| `DuctHazardStripe` | bordes de gate/colapso | naranja/negro sobrio, visible en baja luz |

Reglas:

- Reusar recursos `ShaderMaterial`/`SpatialMaterial` compartidos. No duplicar
  materiales por instancia salvo parámetros de tint de zona.
- Limitar emisión a seams y light strips; la masa principal del ducto queda
  oscura/mate para preservar claustrofobia y rendimiento.
- Las zonas gas/agua/aire se pintan con overlays/tints sutiles, no con una
  variante de material completa por tile.

#### DuctGateValve (Compuerta de Presión) — overlay, no es de topología

```
Propósito:    Compuerta que se cierra — mecánica de presión/urgencia
Geometría:    Marco circular + compuerta deslizante (animación)
Script:       Extiende InteractableBaseV2
              - Animación: compuerta baja de abierto → cerrado en N segundos
              - Señal: gate_state_changed(is_open)
              - Trigger: por proximidad del jugador o por timer global
Archivo:      DuctGateValve.tscn + DuctGateValve.gd
```

La compuerta **no la pide el generador**: el spawner la inserta sobre un brazo
existente (un `DuctRadial`/`DuctArc`) en puntos estratégicos, post-generación.

### 3.3 Cápsulas (Nodos del MST) = junction decorado

Una **cápsula no es un tile aparte de la topología**: es uno de los junctions
(`C`/`T`/`X`) envuelto en una carcasa cilíndrica habitable, con **un puerto
abierto por cada conexión activa** de esa celda. Reusa exactamente la misma
máscara `variant.connections` que usaría el tile de ducto pelado.

Cuando una celda califica como cápsula, **la cápsula reemplaza al tile junction
pelado**. No se instancia encima de `DuctElbow`/`DuctTee`/`DuctCross`, porque eso
duplicaría colisiones y geometría en el mismo volumen.

```
Nombre:       CapsuleRoom
Geometría:    CSGCylinder (radio 3m, altura 4m) +
              2× CSGSphere (radio 3m) en los extremos
              → cápsula farmacéutica de ~10m de alto total

Interior:
  - Suelo de rejilla metálica (plane mesh con alpha)
  - 4 paneles de luz de emergencia (luz puntual roja/cian)
  - Puertos: 1 abertura de radio 2m por cada bit true de variant.connections,
    orientada al brazo correspondiente (radial recto / circunferencial tangente)
  - Válvulas decorativas pequeñas (0.4m, props Pipe* existentes) en las paredes

Colisión:     ConcaveShape generado del CSGCombiner bakeado
Archivo:      CapsuleRoom.tscn (con script CapsuleRoom.gd)

CapsuleRoom.gd:
  - func setup(connections: Array, rotation: int)   # abre solo los puertos activos
  - func open_port(dir: int) / close_port(dir: int) # dir en {N,E,S,W}
  - Señal: port_state_changed(dir, is_open)
```

**Criterio de qué celda es cápsula** (decisión de diseño, ver §3.3.1).

#### 3.3.1 Exponer las "rooms" del generador

Hoy `generate_grid_data` **no dice qué celda fue nodo-semilla del MST**: siembra
las rooms internamente ([ScaffoldMSTGenerator.gd:117](../../core_v2/systems/ScaffoldMSTGenerator.gd#L117))
pero el resultado solo devuelve `{variant, base_height}`. Para colocar cápsulas
hay que surfacearlo. Cambio mínimo en el loop final del generador:

```gdscript
# marcar las celdas que fueron rooms semilla
result[i]["is_room"] = _room_indices.has(i)
```

(`_room_indices` se llena al hacer `rooms.append(...)`, guardando `ry*grid_width+rx`.)

Este cambio no altera topología, alturas, `variant.rotation` ni
`variant.port_heights`: solo expone metadata para que el spawner decida si
reemplaza un junction por `CapsuleRoom`.

**Regla recomendada:** `cápsula = is_room AND grado(celda) >= 2`. Las semillas que
degeneraron en dead-end (`E`) o recto (`W`) no merecen habitación y se quedan como
ducto normal. Así toda cápsula es por definición un `C`/`T`/`X`.

### 3.4 Tabla Completa de Tiles

| Tile | Tipo | Origen | Diámetro | Nuevo? | Archivo |
|---|---|---|---|---|---|
| PipeSection | decorativo | — | 0.4m | existe | `core_v2/props/pipe/PipeSection.tscn` |
| PipeCorner | decorativo | — | 0.4m | existe | `core_v2/props/pipe/PipeCorner.tscn` |
| PipeTee | decorativo | — | 0.4m | existe | `core_v2/props/pipe/PipeTee.tscn` |
| PipeValve | interactivo | — | 0.4m | existe | `core_v2/props/pipe/PipeValve.tscn` |
| DuctEndCap | navegable | variant `E` | 4m | **nuevo** | `core_v2/props/duct/DuctEndCap.tscn` |
| DuctRadial | navegable | variant `W` (0/180) | 4m | **nuevo** | `core_v2/props/duct/DuctRadial.tscn` |
| DuctArc | navegable | variant `W` (90/270) | 4m | **nuevo** | `core_v2/props/duct/DuctArc` (procedural) |
| DuctElbow | navegable | variant `C` | 4m | **nuevo** | `core_v2/props/duct/DuctElbow.tscn` |
| DuctTee | navegable | variant `T` | 4m | **nuevo** | `core_v2/props/duct/DuctTee.tscn` |
| DuctCross | navegable | variant `X` | 4m | **nuevo** | `core_v2/props/duct/DuctCross.tscn` |
| DuctIncline | navegable | variant `S` | 4m | **nuevo** | `core_v2/props/duct/DuctIncline.tscn` |
| DuctGateValve | overlay | spawner | 4m | **nuevo** | `core_v2/props/duct/DuctGateValve.tscn` |
| CapsuleRoom | habitación | room + `C`/`T`/`X` | 6m | **nuevo** | `core_v2/props/duct/CapsuleRoom.tscn` |

## 4. Mecánica de Presión / Colapso

La urgencia del prólogo no viene de elegir rutas en un branching tree. Viene de
que **el entorno se descompone alrededor del jugador**.

### 4.1 Compuertas de Presión (GateValve)

Distribuidas por el maze, las compuertas detectan proximidad del jugador y
comienzan a cerrarse. El jugador debe atravesarlas antes de que sellen.

```
Temporización:
  - Tiempo de cierre: 3-5 segundos desde que el jugador entra en radio de trigger
  - Radio de trigger: 8m delante de la compuerta
  - Al cerrarse completamente: colisión activada, paso bloqueado
  - No reabren (sin vuelta atrás)
```

### 4.2 Fugas y Colapsos

Ciertas secciones tienen fugas activas (reutilizando `GasEmitter`/`LeakEmitter`
de FD-045):

- **Gas (cian):** daño por contacto, visibilidad reducida. El jugador debe
  agacharse o rodear por otra ruta.
- **Agua (azul):** resistencia al movimiento, cámara distorsionada.
- **Aire (transparente):** partículas de viento, sonido de silbido, empuje
  lateral que desestabiliza.

### 4.3 Colapso Progresivo

El colapso se controla principalmente por triggers locales de tramo/cápsula. Un
timer global puede existir como pacing fallback, pero no debe ser la fuente única
de verdad: los triggers locales dan control autoral, evitan sellar rutas antes de
que el jugador llegue, y mantienen el costo de FX cerca del jugador.

Detrás del jugador, secciones de tubo explotan (partículas + sonido + luz de
alarma), y un blocker simple sella el camino recorrido. El blocker es overlay
post-generación, no parte de la topología MST.

## 5. Zonas de Contenido

El maze se divide visualmente en zonas que el MST no controla — se pintan
después de generar la geometría, basado en la posición espacial:

| Zona | Región del cilindro | Contenido | Color | Efecto |
|---|---|---|---|---|
| Gas | Anillos exteriores (r > 10m) | Fugas de plasma frío | Cian | Daño, niebla densa |
| Agua | Anillo medio (6m < r < 10m) | Tuberías con fuga de agua | Azul-verde | Distorsión, resistencia |
| Aire | Anillo interior (r < 6m) | Conductos de ventilación | Gris claro | Visibilidad clara, empuje |
| Núcleo | Centro (r < 2m) | Eje de la nave — vacío o estructura masiva | Negro/rojo | Sin acceso directo |

Las transiciones entre zonas son graduales. Una cápsula en la frontera
gas/agua puede tener ambos efectos.

## 6. Spawner — DuctMazeSpawner

Componente nuevo que envuelve `ScaffoldMSTGenerator`, proyecta las coordenadas
a polares, e instancia los tiles correspondientes.

### 6.1 Arquitectura

```gdscript
class_name DuctMazeSpawner
extends Spatial
tool

# Parámetros del cilindro
export var cylinder_radius := 14.0
export var inner_radius := 2.0
export var cylinder_height := 15.0
export var sectors := 12
export var rings := 6
export var height_steps := 6

# Parámetros del MST
export var room_count := 8
export var extra_cycles := 2
export var seed_value := -1

# Tile libraries — keyed por variant.id que emite el generador
export var duct_tiles: Dictionary  # {E:.., W:.., C:.., T:.., X:.., S:..}
export var capsule_scene: PackedScene

func generate() -> void:
    # 1. Configurar MST Generator con grid params (sectors→grid_width, rings→grid_depth)
    # 2. grid = mst_gen.generate_grid_data(seed_value)
    # 3. Para cada celda i con cell != null (height >= 0):
    #    var v = cell.variant
    #    a. xform = grid_to_world(i % grid_width, i / grid_width, cell.base_height)
    #    b. Elegir geometría:
    #         - v.id == "W": DuctRadial si rotation in {0,180} else DuctArc(radio del anillo)
    #         - v.id == "S": DuctIncline (orientar por rotation + port_heights)
    #         - resto (E/C/T/X): duct_tiles[v.id]
    #    c. Aplicar v.rotation alrededor del eje vertical local del Transform polar
    #    d. Si cell.is_room AND grado(v.connections) >= 2 AND v.id in ["C", "T", "X"]:
    #         capsula = capsule_scene.instance(); capsula.setup(v.connections, v.rotation)
    #       (la cápsula REEMPLAZA al tile pelado, no se suma)
    #    e. Pintar zona de contenido según posición radial (grid_y)
    # 4. Insertar DuctGateValve sobre brazos elegidos (puntos estratégicos)
    # 5. Activar timer/triggers de colapso progresivo
```

> `grado(connections)` = cantidad de bits true. `DuctArc` se construye con el
> radio del anillo de esa celda (§6.2); los demás tiles son escenas estáticas
> rotadas. El `variant.rotation` ya viene resuelto por el generador — el spawner
> no recalcula la firma, solo la consume.

El spawner consume exactamente `{variant, base_height, is_room}`. No infiere
rooms por grado ni recalcula conexiones a partir de vecinos, porque eso duplicaría
la lógica del generador y puede divergir de los contratos de altura.

### 6.2 DuctArc — Mesh Procedural Cacheado

`DuctArc` no puede ser una escena estática porque el `major_radius` varía según
el anillo. En vez de crear una escena por anillo, se genera el mesh en código:

```gdscript
# DuctArcBuilder.gd — genera y cachea un segmento de toro como ArrayMesh
func get_or_build_arc(ring_index: int, major_radius: float, minor_radius: float,
                      arc_degrees: float, segments: int = 12) -> ArrayMesh:
    var cache_key := "%d:%.2f:%.2f:%d" % [ring_index, arc_degrees, minor_radius, segments]
    if _mesh_cache.has(cache_key):
        return _mesh_cache[cache_key]
    var arc_rad := deg2rad(arc_degrees)
    var ring_segments := 8  # resolución de la sección circular
    # ... generación de vértices e índices para un segmento de toro
    # El toro está en el plano XZ con eje Y
    _mesh_cache[cache_key] = mesh
    return mesh
```

La cache evita reconstruir el mismo `ArrayMesh` por instancia. En el layout
default hay solo 6 radios posibles, así que el costo queda acotado.

### 6.3 Presupuesto de Performance

Reglas duras para assets de ductos:

- **No runtime CSG** en `Duct*` ni `CapsuleRoom`. Authorizar como mesh estático o
  hornear con tools, siguiendo el patrón de `tools/bake_airlock_chamber.gd`.
- Usar colisiones simples (`CylinderShape`, `BoxShape`, convex simplificado)
  para tramos rectos y arcos. Reservar `ConcaveShape` para cápsulas o hubs no
  convexos donde sea indispensable.
- FX de fugas, luces dinámicas y gates deben activarse por proximidad/streaming.
  Las piezas lejanas quedan como mesh + material estático.
- Evitar materiales únicos por tile. Compartir material base y usar tint/params
  solo en nodos cercanos si la zona lo requiere.
- Target por tile navegable: pocos MeshInstance, un StaticBody principal, cero
  scripts por-frame salvo gates/FX activos.

## 7. Estructura de la Secuencia

### 7.1 Timeline del Acto 0

| Fase | Duración | Qué pasa |
|---|---|---|
| 1. Entrada | 0:00-0:15 | Elías es eyectado/inyectado en el primer conducto. Cámara en primera persona un segundo, luego 3ra persona. |
| 2. Desorientación | 0:15-0:45 | Tubo recto inicial. El jugador aprende movimiento. Luces de emergencia parpadean. |
| 3. Maze | 0:45-2:00 | Navegación del maze. Colapsos progresivos detrás. Compuertas que se cierran. Zonas de gas/agua/aire. |
| 4. Clímax | 2:00-2:45 | Secuencia final: compuertas en cascada, túnel colapsando, el jugador ve la esclusa al final. |
| 5. Esclusa | 2:45-3:00 | Elías se desliza por la esclusa. Explosión detrás. **Corte a negro.** Título: ODISEA. |
| 6. Empalme | — | Silencio. Despertar criogénico. Acto I. |

### 7.2 Checkpoints

Opción B (del Cold Open doc): checkpoints por segmento, reintento solo del tramo.

- CP1: Después de la fase de desorientación (entrada al maze)
- CP2: Mitad del maze (cápsula segura)
- CP3: Inicio del clímax

## 8. Integración con Acto I

Al despertar en Criogenia, Odisea dice (primer diálogo):

> "Detecté que estuviste activo de nuevo, Elías. Eso no debería ser posible."

Esto preserva la ambigüedad: ¿fue un sueño, un flash-forward, o un evento real
que Odisea monitoreó? El jugador no lo sabe. La semilla de la duda está
plantada.

## 9. Decisiones Abiertas

| # | Decisión | Inclinación |
|---|---|---|
| 1 | ¿El colapso progresivo es global (timer) o local (trigger por zona)? | Local — más control |
| 2 | ¿Las compuertas sellan permanentemente o pueden forzarse con multi-tool? | Permanente en Acto 0 (sin multi-tool aún) |
| 3 | ¿Las cápsulas tienen enemigos o solo atmósfera? | Solo atmósfera — sin DD en Acto 0 |
| 4 | ¿PipeArc como escena variable o mesh procedural? | Mesh procedural (más limpio) |
| 5 | ¿El eje central (r < 2m) es visible desde los ductos? | Sí — ventanas/aberturas que muestran el vacío del núcleo |
| 6 | ¿Música durante el maze? | Solo diseño sonoro (alarmas, fugas, metal crujiendo). Sin BGM hasta el título. |

## 10. Archivos a Crear / Modificar

### Nuevos

```
core_v2/systems/DuctMazeSpawner.gd          — Spawner principal (wrapper de MST + proyección polar)
core_v2/systems/DuctMazeSpawner.tscn
core_v2/systems/DuctArcBuilder.gd           — Mesh procedural para arcos de toro (DuctArc)
core_v2/props/duct/DuctRadial.tscn          — variant W (rot 0/180): tubo recto radial 4m
core_v2/props/duct/DuctElbow.tscn           — variant C: codo radial↔arco
core_v2/props/duct/DuctTee.tscn             — variant T: te 3 brazos
core_v2/props/duct/DuctCross.tscn           — variant X: cruz 4 brazos
core_v2/props/duct/DuctIncline.tscn         — variant S: tubo inclinado (desnivel)
core_v2/props/duct/DuctEndCap.tscn          — variant E: tapa ciega
core_v2/props/duct/DuctGateValve.tscn       — Compuerta de presión (overlay)
core_v2/props/duct/DuctGateValve.gd
core_v2/props/duct/CapsuleRoom.tscn         — Habitación cápsula (junction decorado)
core_v2/props/duct/CapsuleRoom.gd
scenes/levels/act0_duct_maze.tscn           — Escena del nivel Acto 0
scenes/levels/act0_duct_maze.gd
```

> `DuctArc` no tiene .tscn propio: lo construye `DuctArcBuilder.gd` en runtime
> con el radio del anillo. Una sola modificación al generador
> (`ScaffoldMSTGenerator.gd`) para exponer `is_room` por celda — ver §3.3.1.

### Modificados

```
Diseno/Narrativa/Acto_0_Cold_Open.md        — Actualizar referencia a este FD
```

## 11. Verificación

1. MST genera grafo conectado en grid 12×6 con 6 height steps
2. Proyección polar coloca tiles dentro del cilindro de 30m diámetro
3. Cada `variant.id` mapea al tile `Duct*` correcto; `W` elige radial vs arco por `rotation`
4. `DuctArc` conecta celdas E/W con curvatura correcta según el radio de cada anillo
5. El generador expone `is_room` sin cambiar variantes, alturas ni alineación de ports
6. `CapsuleRoom` se instancia solo en rooms con `C`/`T`/`X`, con puertos que coinciden con `variant.connections`, y reemplaza al junction pelado
7. Compuertas se cierran al detectar proximidad del jugador
8. Colapso progresivo local sella secciones detrás del jugador
9. Transición de zonas (gas/agua/aire) es visible y afecta gameplay
10. Ningún ducto/cápsula usa CSG runtime; arcos usan cache por radio
11. Corte a negro al cruzar la esclusa final
12. Primer diálogo de Odisea en Acto I hace referencia ambigua al evento
