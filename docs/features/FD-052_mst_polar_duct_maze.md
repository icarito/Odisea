# FD-052: Acto 0 — Maze de Ductos Radial (MST Polar)

**Status:** Draft v3 (post-mortem corrected)
**Priority:** P1
**Effort:** Medium-High
**Created:** 2026-06-27 (v3 rewrite)
**Depends on:** ScaffoldMSTGenerator (FD-050), AirlockChamber (existente), Pipe props (FD-044)

## 1. Visión General

Prólogo jugable del Acto 0: Elías atraviesa un laberinto de ductos de mantenimiento dentro de
un tanque cilíndrico abandonado (~30m diámetro). La secuencia es cinética, claustrofóbica,
y termina en una esclusa industrial con corte a negro que empalma con el despertar criogénico
del Acto I.

**Lecciones aprendidas de v2:**
- Una tanda de 1 Jules por vez, no paralelos. Sin agolpamiento.
- El spec debe ser completo y correcto antes de encargar.
- No optimizar a mesh temprano — primero que funcione en CSG, luego bake.
- Los tiles A (DuctRadial/DuctArc) son el 80% del maze — no pueden estar rotos.
- Orientación Y/Z debe ser consistente desde el día 1.
- El spawner coordina TODO en un solo script. Sin componentes DuctTile.gd extra.

## 2. Proyección Polar del MST Generator

### 2.1 Principio

El `ScaffoldMSTGenerator` opera sobre un grid 2D abstracto (X, Y) con altura
independiente (Z). Se reinterpretan las coordenadas al instanciar:

```
Grid X → Ángulo θ (circunferencial)
Grid Y → Radio r  (radial)
Height → Altura z (vertical)
```

### 2.2 Convención de Ejes (ODI-001 — NO CAMBIAR)

```gdscript
# Ejes locales de cada pieza de ducto:
# - Z local  → "forward" navegable (eje del tubo)
# - Y local  → up (vertical, cilindro erguido)
# - X local  → lateral (anchura)

# En la proyección polar, el Transform base se construye así:
#   tangent = dirección circunferencial (X local del ducto → arco)
#   radial  = dirección radial (Z local del ducto → forward navegable)
#   up      = siempre Vector3.UP
```

Esto es OBLIGATORIO para todas las piezas. Las IrisDoorV2 existentes esperan
su eje de paso en Z local — y las piezas de ducto deben ser compatibles con
ese contrato. No invertir Z en ningún lado para "arreglar visualmente".

### 2.3 Parámetros del Grid

```
Volumen objetivo:  cilindro diámetro 30m × altura 15m
Radio exterior:    14m
Radio interior:     2m (hueco central)
RING_STEP:          4m (v3 — más espaciado para menos tiles)
grid_width:        12 sectores  → 30° por sector
grid_depth:         3 anillos    → 4m por paso radial
max_height_steps:   6            → 0 a 12m de altura (paso 2m)
HEIGHT_STEP:        2.0m
room_count:         4            (menos rooms, menos junciones complejas)
```

### 2.4 Fórmula de Instanciación

```gdscript
const INNER_RADIUS := 2.0
const RING_STEP := 4.0
const SECTORS := 12
const ANGLE_STEP := 360.0 / SECTORS

func grid_to_world(gx: int, gy: int, height: float) -> Transform:
    var angle_deg := float(gx) * ANGLE_STEP
    var angle_rad := deg2rad(angle_deg)
    var radius := INNER_RADIUS + (float(gy) + 0.5) * RING_STEP

    var world_x := radius * cos(angle_rad)
    var world_z := radius * sin(angle_rad)
    var pos := Vector3(world_x, height, world_z)

    # Basis: X=tangent (lateral/anchura del ducto)
    #        Y=up       (vertical/arriba del ducto)
    #        Z=radial   (forward navegable del ducto)
    var tangent := Vector3(-sin(angle_rad), 0, cos(angle_rad))
    var up := Vector3.UP
    var radial := Vector3(cos(angle_rad), 0, sin(angle_rad))

    return Transform(Basis(tangent, up, radial), pos)
```

`variant.rotation` se aplica alrededor del eje Y local después de construir
este basis. Es decir:

```gdscript
instance.transform = grid_to_world(gx, gy, cell.base_height)
instance.rotate_object_local(Vector3.UP, deg2rad(v.rotation))
```

No invertir Z. No rotar alrededor de otro eje. No recalcular ports.

## 3. Capa de Física (Camera passthrough)

Los ductos NO están en la layer de Entorno (1). Están en la layer **Prop**
(bit 6, layer 7).

- La cámara (`SpringArm`) tiene `camera_collision_mask` = `mask_layers([1,4])`
  = capas Entorno + CameraCollision, **sin Prop (layer 7)**.
  → La cámara atraviesa las paredes y ves el interior del ducto.
- El jugador colisiona con layer 7 porque su `collision_mask` lo incluye.

Regla fija en el spawner:
```gdscript
const DUCT_COLLISION_LAYER = 1 << 6  # bit 6 = layer 7
# collision_layer = DUCT_COLLISION_LAYER
# collision_mask = 0 (o 255, solo colisiona con jugador)
```

## 4. Diseño Visual de Ductos

Cada tile navegable tiene:

1. **Carcasa translúcida** — mesh semi-transparente con alpha ~0.3, color #1a1a1e,
   roughness 0.9. La cámara la atraviesa (layer Prop), el jugador colisiona.
2. **Anillos estructurales** — cada ~4m de tramo, un aro metálico opaco
   (albedo #3a3a40, metallic 0.5, roughness 0.6). Dan escala y sensación industrial.
3. **Piso de rejilla** — banda caminable en la parte inferior, alpha cutout.
4. **Strips de luz de emergencia** — líneas cian tenues en seams, emisión baja.

**Referencia visual directa:** `core_v2/props/doors/AirlockChamber.tscn`.
Mismo lenguaje de materiales, misma paleta industrial oscura.

### Materiales compartidos (assets existentes, creados por Jules en v2):

| Recurso | Path |
|---|---|
| DuctHull | `res://core_v2/props/duct/DuctHull.tres` |
| DuctFloorGrate | `res://core_v2/props/duct/DuctFloorGrate.tres` |
| DuctLightStrip | `res://core_v2/props/duct/DuctLightStrip.tres` |
| DuctConduit | `res://core_v2/props/duct/DuctConduit.tres` |
| DuctHazardStripe | `res://core_v2/props/duct/DuctHazardStripe.tres` |

## 5. Tiles Navegables

7 variantes derivadas del MST generator. Diámetro interno 4m (radio 2m).

| variant.id | Significado | Geometría | Notas |
|---|---|---|---|
| E | Dead-end | stub ciego 1m + anillo final | tapa opaca no translúcida |
| W (rot 0/180) | Recto radial | cilindro hueco 4m, eje Z, RING_STEP=4m | tile más común (~40% del maze) |
| W (rot 90/270) | Arco circunf | arco de toro procedural, major_r según gy | mesh procedural cacheado |
| C | Junction 2 brazos | hub esférico r2.5m + 2 brazos (rad+circ) | 1 junction cada ~8 celdas |
| T | Junction 3 brazos | hub + 3 brazos (rad+circ+circ/rad) | raro |
| X | Junction 4 brazos | hub + 4 brazos | muy raro (solo en rooms) |
| S | Recto inclinado | cilindro inclinado según port_heights | desnivel |

### 5.1 Contrato de geometría de cada tile

**Reglas absolutas para TODOS los tiles:**
- Eje navegable del tubo = Z local (forward). Compatible con IrisDoorV2.
- Radio interno = 2.0m. Pared = 0.35m (radio externo ~2.35m).
- Anillos estructurales cada 4m sobre el eje del tubo.
- Piso de rejilla en la banda inferior (de 0 a -1.5 en Y local).
- Layer Prop (bit 6). StaticBody + CylinderShape para rectos.
- Sin CSG runtime. Sin scripts runtime en tiles individuales.

### 5.2 DuctArc — Mesh Procedural

Se genera con `DuctArcBuilder.gd` (ya existe en `core_v2/systems/DuctArcBuilder.gd`):

```gdscript
static func get_or_build_arc(major_r: float, minor_r: float,
                              arc_deg: float, segments: int = 12) -> ArrayMesh
```

Caché por clave `major_r:minor_r:arc_deg:segments`. Con solo 3 anillos, hay
máximo 3 meshes cacheados.

**ADVERTENCIA — error de orientación conocido:** En la implementación previa,
el DuctArc tenía un offset de rotación que no coincidía con el transform
`grid_to_world`. Para corregir:

- El arco se genera en el plano XZ con eje Y como normal del toro.
- El spawner lo coloca SIN rotación extra si el basis ya está orientado
  tangente→X, up→Y, radial→Z. Si el arco necesita un cuarto de vuelta
  adicional, eso va en `variant.rotation`, no en la geometría.

### 5.3 Colisión

```
- DuctRadial / DuctIncline: CylinderShape(radius=2.0, height=RING_STEP)
- DuctArc: CylinderShape curved simulation o colisión por segmentos
- Junctions (C/T/X): CollisionShape con SphereShape(radius=2.5) +
  CylinderShape por cada brazo entrante
- DuctEndCap: CylinderShape(radius=2.35, height=1.0) sólido
```

## 6. Cápsulas (Nodos MST)

Las cápsulas **NO usan AirlockChamber.tscn** en v3. Usan un mesh procedural
único generado por el spawner, con geometría de cápsula farmacéutica:

- CSGCylinder(radio=3m, altura=4m) + 2× semiesferas en extremos → ~10m total
- Puertos circulares r2m en las direcciones de sus conexiones activas
- Interior decorado: paneles de luz, válvulas PipeValve decorativas

**Criterio:** `cell.is_room AND grado(connections) >= 2 AND variant.id in ["C","T","X"]`

La cápsula REEMPLAZA al tile junction. Contiene:
- El hub central (cámara habitable)
- Brazos que conectan a los puertos activos
- Una OmniLight de zona (gas/agua/aire)
- Sin scripts runtime

## 7. Airlocks de Entrada/Salida

- **Entrada:** Primera cápsula. Puerta detrás sellada al avanzar. Usa IrisDoorV2.
- **Salida:** Última cápsula (más lejana radialmente en el último height step).
  IrisDoorV2 funcional. El jugador activa → cierre → descompresión → corte a
  negro → transición al Acto I.

Puesta en escena de la salida: la cápsula final es un AirlockChamber real
(`core_v2/props/doors/AirlockChamber.tscn`). Es la única que usa esa escena.

## 8. DuctMazeStreamer (Spawner Único)

```gdscript
class_name DuctMazeStreamer
extends Spatial
tool

# Parámetros del cilindro
export var inner_radius := 2.0
export var ring_step := 4.0
export var sectors := 12
export var rings := 3
export var height_steps := 6
export var room_count := 4
export var extra_cycles := 2
export var seed_value := -1

# Visual
export var duct_radius := 2.0
export var duct_wall_thickness := 0.35
export var ring_spacing := 4.0
export var ring_height := 0.15
export var ring_extra_radius := 0.35

const DUCT_LAYER := 1 << 6  # bit 6 = layer 7 (Prop)

func generate() -> void:
    # 1. Crear ScaffoldMSTGenerator, generar grid
    # 2. Para cada celda con cell != null:
    #    a. Calcular transform con grid_to_world(gx, gy, cell.base_height)
    #    b. Aplicar v.rotation alrededor de Y local
    #    c. Elegir tile: DuctRadial/DuctArc para "W", DuctIncline para "S",
    #       junction pelado o cápsula para C/T/X/E
    #    d. Construir mesh procedural + StaticBody + CollisionShape
    #    e. Añadir anillos estructurales
    #    f. Piso de rejilla
    #    g. Añadir overlay de zona (gas/agua/aire)
    # 3. Insertar airlock de salida (AirlockChamber con IrisDoorV2)
    # 4. Configurar triggers de colapso progresivo
```

### 8.1 Métodos clave

```gdscript
func _grid_to_world(gx, gy, height) -> Transform    # §2.4
func _make_duct_radial(gy) -> Spatial                 # cilindro recto
func _make_duct_arc(gx, gy) -> Spatial                # arco procedural
func _make_junction(id, connections) -> Spatial       # C/T/X hub + brazos
func _make_incline(port_heights) -> Spatial           # recto inclinado
func _make_endcap() -> Spatial                        # tapa ciega
func _make_capsule(connections, gy) -> Spatial         # habitación grande
func _add_structural_rings(parent, axis, length, radius, count)
func _add_floor_grate(parent, length, radius)
func _add_content_overlay(node, gy)                   # luz + partículas
```

### 8.2 Colapso Progresivo

Post-generación, triggers locales por tramo:

- Trigger de proximidad. Al activarse: instancia DuctEndCap opaco (sólido,
  layer Prop) detrás del jugador + FX partículas + sonido.
- No usar CSG runtime. No usar mesh procedural cambiante.
- Timer global como fallback, no fuente principal.

## 9. Zonas de Contenido

Post-generación, pintar según posición radial:

| Zona | grid_y | Efecto visual | Gameplay |
|---|---|---|---|
| Gas | >= 2 (r > 10m) | OmniLight cian, niebla, tint material | Daño por contacto, visibilidad reducida |
| Agua | == 1 (6m < r < 10m) | OmniLight azul, partículas burbuja | Resistencia movimiento, cámara distorsionada |
| Aire | == 0 (r < 6m) | OmniLight gris tenue | Visibilidad clara |

Solo en cápsulas (rooms) para no saturar de luces dinámicas.

## 10. Estructura de la Secuencia

| Fase | Duración | Eventos |
|---|---|---|
| 1. Entrada | 0:00-0:15 | Elías eyectado en ducto. IrisDoor se sella detrás. |
| 2. Maze | 0:15-1:45 | Navegación, colapsos progresivos, zonas de contenido. |
| 3. Clímax | 1:45-2:30 | Compuerta final, túnel colapsando, esclusa visible. |
| 4. Salida | 2:30-2:45 | Airlock se cierra, descompresión, corte a negro. Título: ODISEA. |
| 5. Empalme | — | Silencio. Despertar criogénico. Acto I. |

## 11. Archivos

### Existentes (NO TOCAR salvo bugfix)
- `core_v2/props/doors/AirlockChamber.tscn` — modelo de la esclusa final
- `core_v2/components/IrisDoorV2.gd` + .tscn — puertas de airlock
- `core_v2/props/pipe/PipeValve.tscn` + .gd — decoración interior
- `core_v2/systems/ScaffoldMSTGenerator.gd` — añadir export `is_room` por celda

### A modificar
- `core_v2/systems/DuctMazeSpawner.gd` → **DuctMazeStreamer** (rewrite completo,
  mesh procedural, sin .tscn de tiles individuales)
- `core_v2/systems/DuctArcBuilder.gd` — fix de orientación Y/Z (arco debe
  alinearse con Z=forward del transform polar)
- `scenes/levels/act0_duct_maze.tscn` — escena que instancia DuctMazeStreamer

### A ELIMINAR
- `core_v2/props/duct/DuctEndCap.tscn`
- `core_v2/props/duct/DuctRadial.tscn`
- `core_v2/props/duct/DuctElbow.tscn` + .gd
- `core_v2/props/duct/DuctTee.tscn`
- `core_v2/props/duct/DuctCross.tscn`
- `core_v2/props/duct/DuctIncline.tscn`
- `core_v2/props/duct/CapsuleRoom.tscn` + .gd
- `core_v2/props/duct/DuctGateValve.tscn` + .gd
- `core_v2/props/duct/DuctTile.gd`
- `core_v2/systems/DuctMazeSpawner.tscn`

### Tests
- `tests/smoke_duct_maze.gd` — smoke test de generación (no PR en producción)

## 12. Estrategia de Implementación (por Jules, una tanda a la vez)

### Tanda 1: DuctMazeStreamer base (DuctRadial + DuctArc)
1. Arreglar `_grid_to_world` en el spawner — Z=forward, sin invertir.
2. Implementar `_make_duct_radial` — cilindro hueco con anillos, piso, layer Prop.
3. Corregir `DuctArcBuilder.gd` — la orientación del arco debe corresponder 1:1
   al basis tangente+radial del spawner.
4. `generate()` corre y coloca al menos 80% de las celdas como rectos/arcos.

### Tanda 2: Junctions + Cápsulas
5. `_make_junction()` para C/T/X con hub esférico + brazos.
6. `_make_capsule()` — reemplazo de junction por habitación.
7. Colapso progresivo (triggers + blocker).

### Tanda 3: Airlocks + Zonas + Pulido
8. Airlock de salida con IrisDoorV2.
9. Overlays de zona (gas/agua/aire).
10. Smoke test. Corre en escena sin crashear. Cámara pasa a través de paredes.

## 13. Verificación

1. `rings=3` → 3 anillos, 12 sectores → ~36 celdas generadas
2. Todas las celdas con conexión ≠ `null` tienen transform válido
3. El jugador camina por el interior de los ductos sin clipping
4. La cámara pasa a través de las paredes (layer Prop)
5. Los ductos radiales conectan con arcos circunferenciales sin gap visible
6. Las cápsulas tienen puertos solo en direcciones con conexión activa
7. El airlock de salida carga IrisDoorV2 y transiciona a Acto I
8. Los triggers de colapso instancian blocker detrás del jugador
9. `room_count=4` produce exactamente 4 o menos cápsulas
