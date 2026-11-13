# FD-052 v2: Acto 0 — Derelict Duct Maze / Laberinto de Ductos Abandonados

**Status:** Draft v2  
**Priority:** P1  
**Effort:** Medium  
**Created:** 2026-06-27  
**Depends on:** ScaffoldMSTGenerator (FD-050), AirlockChamber (existente), Pipe props (FD-044)

## 1. Visión General

Prólogo jugable del Acto 0: Elías atraviesa un laberinto de ductos de mantenimiento dentro de un tanque cilíndrico abandonado (~30m diámetro). La secuencia es cinética, claustrofóbica, y termina en una esclusa industrial que conecta con el módulo criogenia del Acto I.

**Cambios clave respecto a v1:**
- Ductos transparentes en layer de Props (cámara los atraviesa, jugador colisiona)
- Anillos estructurales cada ~4m en lugar de mesh liso
- Cápsulas grandes (~10m) usando AirlockChamber como referencia visual
- Airlocks de entrada/salida (no iris doors dentro del maze)
- Sin tiles prefabricados CSG — todo mesh procedural o estático baked
- Sin streaming por ahora (maze pequeño, 12×6)

## 2. Capas de Física (Camera passthrough)

Los ductos NO están en la layer Entorno (1). Están en la layer **Prop (bit 6, layer 7)**. La cámara spring arm tiene `camera_collision_mask = 129` (Entorno+CameraCollision, sin Prop), así que la cámara pasa **a través** de las paredes de ducto y ves el interior normalmente. El jugador colisiona con Prop porque su `collision_mask` incluye layer 7.

Regla: todo StaticBody del maze se pone en `collision_layer = 1 << 6`, `collision_mask = 255`.

## 3. Diseño Visual de los Ductos

Cada tile navegable de ducto no es un cilindro liso. Tiene:

1. **Carcasa translúcida** — mesh semi-transparente con alpha ~0.3, color #1a1a1e, roughness 0.9. Se ve la estructura interior a través de las paredes.
2. **Anillos estructurales** — cada ~4m de tramo, un aro metálico opaco (albedo #3a3a40, metallic 0.5, roughness 0.6). Espaciado uniforme. Dan la referencia de escala y la sensación industrial.
3. **Piso de rejilla** — banda caminable en la parte inferior, alpha cutout, diamond plate.
4. **Strips de luz de emergencia** — líneas cian tenues en los seams, emisión baja.
5. **Conduits decorativos** — cañerías pequeñas (Pipe*) en el exterior.

**Referencia visual directa:** `core_v2/props/doors/AirlockChamber.tscn`. Los ductos deben leerse como extensiones del mismo sistema de mantenimiento — mismo lenguaje de materiales, misma paleta industrial oscura.

## 4. Tiles Navegables (mesh procedural + estático)

7 variantes derivadas del MST generator. Diámetro interno 4m (radio 2m), pared translúcida ~0.35m.

| variant.id | Tile | Geometría |
|---|---|---|
| E | DuctEndCap | stub ciego 1m + anillo final opaco. 1 conexión. |
| W rot 0/180 | DuctRadial | tramo recto radial 4m (RING_STEP=4m en v2). 2 conexiones opuestas. |
| W rot 90/270 | DuctArc | arco circumferencial, mesh procedural por radio de anillo. 2 conexiones opuestas. |
| C | DuctElbow | codo: hub esférico r2.5m + 2 brazos (recto radial + arco tangente). |
| T | DuctTee | te: hub + 3 brazos. |
| X | DuctCross | cruz: hub + 4 brazos. |
| S | DuctIncline | tramo recto desnivelado (inclinación vía port_heights del MST). |

**Todos los tiles tienen:** carcasa semi-transparente, anillos estructurales cada ~4m, piso de rejilla, y están en layer Prop (bit 6). Sin scripts runtime.

Los anillos estructurales se modelan como **MeshInstance** con CylinderMesh hueco (top_radius 2.35, bottom_radius 2.35, height 0.15, interior radius 2.0) o un toro simplificado. Se colocan a intervalos regulares sobre el eje del tubo.

## 5. Cápsulas (nodos MST decorados)

No hay un tile CapsuleRoom aparte. Las cápsulas son **AirlockChamber.tscn** (ya existe en `core_v2/props/doors/`) reutilizado y escalado como habitación.

- **Geometría:** la escena AirlockChamber (~radio 3m, altura ~4m) escalada al tamaño de una celda del grid (~Radio 6m, altura 8m)
- **Puertos:** mismo contrato que DuctPort — 1 abertura circular r2m por cada conexión activa de la celda
- **Interior:** el interior del AirlockChamber + válvulas PipeValve decorativas en paredes
- **Airlock operativo:** cuando una cápsula es la entrada o salida del maze, tiene un airlock funcional (IrisDoorV2 en la abertura, interactuable para abrir/cerrar)

**Criterio:** `is_room AND grado >= 2 AND id in ["C","T","X"]`. La cápsula REEMPLAZA al tile junction pelado. No se instancia encima.

## 6. Airlocks de Entrada/Salida

Dos cápsulas especiales:

- **Entrada:** al inicio del maze, una AirlockChamber con la puerta de entrada cerrada detrás del jugador. Al avanzar, la puerta se sella (no vuelta atrás).
- **Salida:** al final del maze, una AirlockChamber con iris door funcional. El jugador la activa → cierre → descompresión → corte a negro → Acto I.

Ambas usan IrisDoorV2 (existente en `core_v2/components/IrisDoorV2.gd` + `core_v2/props/doors/IrisDoorV2.tscn`).

## 7. DuctMazeSpawner (coordinador único)

```gdscript
class_name DuctMazeStreamer extends Spatial tool

# Parámetros del cilindro
export var inner_radius := 2.0
export var ring_step := 4.0  # en v2 subimos a 4m
export var sectors := 12
export var rings := 6
export var height_steps := 6
export var room_count := 4
export var extra_cycles := 2
export var seed_value := -1

# Parámetros visuales
export var duct_radius := 2.0
export var duct_wall_thickness := 0.35
export var ring_spacing := 4.0  # cada cuántos metros va un anillo estructural
export var ring_height := 0.15
export var ring_extra_radius := 0.35  # anillo sobresale de la pared

# Layers
const DUCT_COLLISION_LAYER = 1 << 6  # bit 6 = layer 7 (Prop)

func generate() -> void: ...
func _make_procedural_tile(connections, port_heights, radius, is_room) -> Spatial: ...
func _append_cylinder_shell(data, center, axis, length, radius, segments, double_sided): ...
func _append_ring(data, center, axis, inner_r, outer_r, height, segments): ...
```

El spawner construye mesh procedural con double_sided = true para todos los shells visuales. Los anillos estructurales se generan como cilindros huecos (inner/outer radius) a intervalos de `ring_spacing` a lo largo del eje del tubo.

**No usa CSG en ningún tile.** Todo mesh ArrayMesh + StaticBody + CollisionShape.

## 8. Colapso Progresivo (post-generación)

Después de generar el maze, el spawner inserta triggers de colapso:

- Triggers locales por tramo/cápsula
- Al activarse: instancia un **DuctEndCap** opaco (no translucent) detrás del jugador, + FX de partículas (polvo, chispas) + sonido
- No usar CSG runtime ni mesh procedural para blockers — reusar DuctEndCap existente
- Timer global como fallback, no como fuente principal de pacing

## 9. Zonas de Contenido (overlays)

Post-generación, pintar según posición radial (grid_y):

- Gas (grid_y >= 4, r>10m): OmniLight cian + niebla (ParticlesMaterial) + tint de material 30%
- Agua (2 <= grid_y < 4): OmniLight azul + tint + partículas de burbuja
- Aire (grid_y < 2): sin overlay extra

Solo en cápsulas (rooms) para no saturar de luces.

## 10. Archivos a Crear / Modificar

### Modificar (el que ya existe en tu máquina local)
- `core_v2/systems/DuctMazeSpawner.gd` — rewrite completo como DuctMazeStreamer (914 líneas actualmente)

### Archivos existentes que NO se tocan (reutilizar)
- `core_v2/props/doors/AirlockChamber.tscn` — usado como base visual y como cápsula
- `core_v2/components/IrisDoorV2.gd` — airlocks de entrada/salida
- `core_v2/props/doors/IrisDoorV2.tscn`
- `core_v2/props/pipe/PipeValve.tscn` + .gd — decoración interior

### Archivos que se ELIMINAN
- `core_v2/props/duct/DuctEndCap.tscn` — reemplazado por mesh procedural
- `core_v2/props/duct/DuctRadial.tscn` — reemplazado por mesh procedural
- `core_v2/props/duct/DuctElbow.tscn` — reemplazado por mesh procedural
- `core_v2/props/duct/DuctElbow.gd`
- `core_v2/props/duct/DuctTee.tscn`
- `core_v2/props/duct/DuctCross.tscn`
- `core_v2/props/duct/DuctIncline.tscn`
- `core_v2/props/duct/CapsuleRoom.tscn`
- `core_v2/props/duct/CapsuleRoom.gd`
- `core_v2/props/duct/DuctGateValve.tscn`
- `core_v2/props/duct/DuctGateValve.gd`
- `core_v2/systems/DuctArcBuilder.gd`
- `core_v2/systems/DuctMazeSpawner.tscn` (obsoleto)

### Escenas de nivel
- `scenes/levels/act0_duct_maze.tscn` — escena del nivel (crear)
- `scenes/levels/act0_duct_maze.gd` — script del nivel (crear, setup básico)

### Tests
- `tests/DuctPieceTestScene.gd` — mantener para pruebas visuales offline
- `tests/DuctPieceTestScene.tscn`

## 11. Qué NO hacer

- No CSG runtime en ningún tile navegable
- No tiles prefabricados .tscn — todo mesh procedural desde el spawner
- No iris doors dentro del maze (solo en entrada/salida)
- No enemigos (sin DDC en Acto 0)
- No multi-tool (aún no la tiene Elías)
- No streaming por ahora (maze en un solo chunk)
- No música (solo diseño sonoro)
