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

| Dirección MST | Significado físico | Tile |
|---|---|---|
| EAST/WEST | Conexión circunferencial | **PipeArc** (tubo curvo, arco de circunferencia) |
| NORTH/SOUTH | Conexión radial | **PipeSection** (tubo recto radial) |
| Height delta | Conexión vertical | **PipeVertical** (tubo recto ascendente/descendente) |

Las conexiones EAST/WEST se vuelven arcos de circunferencia a radio constante.
Las NORTH/SOUTH se vuelven tubos rectos en dirección radial. Los cambios de
altura son tubos verticales puros.

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

    # La base Y del tile apunta hacia afuera (radial)
    # La base X del tile apunta en dirección circunferencial (tangente)
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
(radio 2m), paredes de 0.1m de espesor.

Todos heredan de `Spatial`. Colisión `StaticBody` + `CylinderShape`/`ConcaveShape`.

#### PipeArc (Arco Circunferencial)

```
Propósito:    Conexión EAST/WEST — arco de circunferencia a radio constante
Geometría:    Segmento de toro (CSGTorus o mesh custom):
              - major_radius = radio del anillo en ese grid_y
              - minor_radius = 2.0 (radio del tubo)
              - arc_degrees = 30° (ANGLE_STEP)
Orientación:  El eje del toro es vertical (Y up). El arco recorre en XZ.
Variantes:    Ninguna (siempre mismo ángulo, 30°)
Archivo:      PipeArc.tscn
```

La major_radius varía según el anillo. Esto implica que `PipeArc` necesita
recibir el radio como parámetro al instanciar, o se calcula en el spawner.
Alternativa: hacer el mesh procedural en GDScript en vez de escenas pre-hechas.

#### PipeSection (Tubo Radial)

```
Propósito:    Conexión NORTH/SOUTH — tubo recto en dirección radial
Geometría:    Cilindro hueco, radio 2.0, largo = RING_STEP (2m)
Orientación:  Eje del cilindro alineado con la dirección radial (Z local)
              del Transform de la celda
Archivo:      PipeSection4m.tscn (variante grande del existente)
```

#### PipeVertical (Tubo Vertical)

```
Propósito:    Cambio de altura entre celdas conectadas con height delta
Geometría:    Cilindro hueco, radio 2.0, largo = HEIGHT_STEP (2m)
Orientación:  Eje del cilindro vertical (Y up)
Archivo:      PipeVertical.tscn
```

#### PipeCross (Intersección en X — 4 direcciones)

```
Propósito:    Nodo con 4 salidas horizontales (N/S/E/W)
Geometría:    Esfera central (radio 2.5) + 4 brazos cortos de cilindro
              apuntando a 0°, 90°, 180°, 270°
Archivo:      PipeCross4m.tscn
```

#### EndCap (Tapa de Conducto)

```
Propósito:    Cerrar ramas sin salida (celdas con 1 sola conexión)
Geometría:    Disco metálico con reborde, radio 2.0
Archivo:      PipeEndCap.tscn
```

#### GateValve (Compuerta de Presión)

```
Propósito:    Compuerta que se cierra — mecánica de presión/urgencia
Geometría:    Marco circular + compuerta deslizante (animación)
Script:       Extiende InteractableBaseV2
              - Animación: compuerta baja de abierto → cerrado en N segundos
              - Señal: gate_state_changed(is_open)
              - Trigger: por proximidad del jugador o por timer global
Archivo:      PipeGateValve.tscn + PipeGateValve.gd
```

### 3.3 Cápsulas (Habitaciones — Nodos del MST)

Cada celda del grid que el MST marca como "room" (nodo conectado) aloja una
**cápsula**. Es una habitación cilíndrica con extremos abovedados, construida
con primitivas de Godot.

```
Nombre:       CapsuleRoom
Geometría:    CSGCylinder (radio 3m, altura 4m) +
              2× CSGSphere (radio 3m) en los extremos superior e inferior
              → Forma de cápsula farmacéutica de ~10m de alto total

Interior:
  - Suelo de rejilla metálica (plane mesh con alpha)
  - 4 paneles de luz de emergencia (luz puntual roja/cian)
  - Puertos en paredes: aberturas circulares de radio 2m donde conectan los tubos
  - Un puerto por cada conexión activa del MST en esa celda
  - Válvulas decorativas pequeñas (0.4m) en las paredes

Colisión:     ConcaveShape generado del CSGCombiner bakeado
Archivo:      CapsuleRoom.tscn (con script CapsuleRoom.gd)

CapsuleRoom.gd:
  - export(Array, NodePath) var connected_pipes: Array
  - func open_port(index: int) / close_port(index: int)
  - Señal: port_state_changed(port_index, is_open)
```

### 3.4 Tabla Completa de Tiles

| Tile | Tipo | Diámetro | Nuevo? | Archivo |
|---|---|---|---|---|
| PipeSection | decorativo | 0.4m | existe | `core_v2/props/pipe/PipeSection.tscn` |
| PipeCorner | decorativo | 0.4m | existe | `core_v2/props/pipe/PipeCorner.tscn` |
| PipeTee | decorativo | 0.4m | existe | `core_v2/props/pipe/PipeTee.tscn` |
| PipeValve | interactivo | 0.4m | existe | `core_v2/props/pipe/PipeValve.tscn` |
| PipeArc | navegable | 4m | **nuevo** | `core_v2/props/duct/PipeArc.tscn` |
| PipeSection4m | navegable | 4m | **nuevo** | `core_v2/props/duct/PipeSection4m.tscn` |
| PipeVertical | navegable | 4m | **nuevo** | `core_v2/props/duct/PipeVertical.tscn` |
| PipeCross4m | navegable | 4m | **nuevo** | `core_v2/props/duct/PipeCross4m.tscn` |
| PipeEndCap | navegable | 4m | **nuevo** | `core_v2/props/duct/PipeEndCap.tscn` |
| PipeGateValve | navegable | 4m | **nuevo** | `core_v2/props/duct/PipeGateValve.tscn` |
| CapsuleRoom | habitación | 6m | **nuevo** | `core_v2/props/duct/CapsuleRoom.tscn` |

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

Un timer global activa eventos de colapso a intervalos. Detrás del jugador,
secciones de tubo explotan (partículas + sonido + luz de alarma), sellando el
camino recorrido. Esto fuerza avance constante sin posibilidad de backtracking.

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

# Tile libraries
export var duct_tiles: Dictionary  # {W: PackedScene, C: PackedScene, ...}
export var capsule_scene: PackedScene

func generate() -> void:
    # 1. Configurar MST Generator con grid params
    # 2. Ejecutar MST
    # 3. Para cada celda con height >= 0:
    #    a. Calcular posición polar → world Transform
    #    b. Instanciar tile según variant
    #    c. Si es room: instanciar CapsuleRoom
    #    d. Pintar zona de contenido según posición radial
    # 4. Instanciar compuertas en puntos estratégicos
    # 5. Activar timer de colapso progresivo
```

### 6.2 PipeArc — Mesh Procedural

`PipeArc` no puede ser una escena estática porque el `major_radius` varía según
el anillo. En vez de crear una escena por anillo, se genera el mesh en código:

```gdscript
# PipeArcBuilder.gd — genera un segmento de toro como ArrayMesh
func build_pipe_arc(major_radius: float, minor_radius: float,
                    arc_degrees: float, segments: int = 12) -> ArrayMesh:
    var arc_rad := deg2rad(arc_degrees)
    var ring_segments := 8  # resolución de la sección circular
    # ... generación de vértices e índices para un segmento de toro
    # El toro está en el plano XZ con eje Y
```

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
core_v2/systems/PipeArcBuilder.gd           — Mesh procedural para arcos de toro
core_v2/props/duct/PipeArc.tscn             — (o generado en código)
core_v2/props/duct/PipeSection4m.tscn       — Tubo recto radial 4m diámetro
core_v2/props/duct/PipeVertical.tscn        — Tubo vertical 4m diámetro
core_v2/props/duct/PipeCross4m.tscn         — Intersección X 4m diámetro
core_v2/props/duct/PipeEndCap.tscn          — Tapa ciega
core_v2/props/duct/PipeGateValve.tscn       — Compuerta de presión
core_v2/props/duct/PipeGateValve.gd
core_v2/props/duct/CapsuleRoom.tscn         — Habitación cápsula
core_v2/props/duct/CapsuleRoom.gd
scenes/levels/act0_duct_maze.tscn           — Escena del nivel Acto 0
scenes/levels/act0_duct_maze.gd
```

### Modificados

```
Diseno/Narrativa/Acto_0_Cold_Open.md        — Actualizar referencia a este FD
```

## 11. Verificación

1. MST genera grafo conectado en grid 12×6 con 6 height steps
2. Proyección polar coloca tiles dentro del cilindro de 30m diámetro
3. PipeArc conecta celdas EAST/WEST con curvatura correcta por anillo
4. CapsuleRoom se instancia en nodos con puertos que coinciden con tubos conectados
5. Compuertas se cierran al detectar proximidad del jugador
6. Colapso progresivo sella secciones detrás del jugador
7. Transición de zonas (gas/agua/aire) es visible y afecta gameplay
8. Corte a negro al cruzar la esclusa final
9. Primer diálogo de Odisea en Acto I hace referencia ambigua al evento
