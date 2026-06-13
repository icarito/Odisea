# FD-174: Scene Precomputed Geometry for 3D Dashboard View

## Context

El juego Odisea tiene escenas con geometría estática (Criogenia, OdiseaExterior, Dome_Crio, etc.) y escenas procedurales (ScaffoldOrbit con WFC). El dashboard ya tiene una vista 3D (Viewport3D.tsx con Three.js) que intenta cargar `game-assets/{scene}.glb` pero esos archivos no existen — el viewport solo muestra ghost markers sobre grid vacío.

Necesitamos que la vista 3D del dashboard muestre la geometría del nivel para contextualizar la posición del player y sus ghosts.

## Objetivo

Crear un pipeline que precompute la geometría de las escenas del juego desde Godot y la sirva al dashboard para renderizar en la vista 3D (Viewport3D) y la vista birdseye (LiveMap).

## Scope — qué incluimos y qué no

### IN SCOPE (ahora)
- **Escenas estáticas**: Criogenia, OdiseaExterior, Dome_Crio, Interiors de referencia
- **Props de todas las escenas**: LeakEmitter, Lever, PipeValve, PushableBox, PedestalButton, etc. — todos deben aparecer en el mapa con posición y tipo
- **Rotators (CylinderRotator)**: exportar su AABB máximo + tag `"rotator"`
- **JSON por escena**: point cloud + bounding boxes de zonas + lista de props
- **Dashboard consumer**: SceneGeometry.tsx (Three.js) que consume los JSON
- **Birdseye view**: LiveMap.tsx dibujando contorno de geometría proyectada en 2D + props como dots

### NOT IN SCOPE (ahora)
- ScaffoldOrbit procedural — el chunk backbone se genera en runtime con WFC. Eventualmente el script Godot tool cargará la escena con `global_seed=42` (valor default), hará bake del chunk base, y exportará eso. Pero no ahora.
- Rotators/WorldRotator animados — solo AABB estático por ahora
- Streaming de geometría — se sirve como archivo estático (JSON precargado)

## Arquitectura

### A. Script Godot: `tools/export_scene_geometry.gd`

Script `tool` que se ejecuta en el editor de Godot. Recibe parámetros, exporta un archivo JSON por escena.

**Input:**
- Path a escena `.tscn`
- Resolución de sampleo (default: cada 2 unidades)
- `--include-props` (default: true)
- `--output-dir` (default: `exported_scenes/`)
- `--seed` (opcional, para escenas procedurales — reservado para futuro)

**Output por escena — archivo JSON:**
```json
{
  "scene": "OdiseaExterior",
  "version": 1,
  "bounds": {
    "min": [-100, 0, -100],
    "max": [100, 20, 100]
  },
  "points": [
    [x, y, z],
    ...
  ],
  "zones": [
    {
      "name": "Puente Central",
      "bounds": {"min": [-10, 0, -10], "max": [10, 4, 10]},
      "walkable": true,
      "type": "platform"
    }
  ],
  "props": [
    {
      "name": "LeakEmitter_01",
      "position": [5, 2, -3],
      "bounds": {"min": [4, 1, -4], "max": [6, 3, -2]},
      "type": "prop",
      "tags": ["interactable", "hazard"]
    }
  ],
  "metadata": {
    "generated_at": "2026-06-13",
    "point_count": 5000,
    "zone_count": 3,
    "prop_count": 12
  }
}
```

### B. Procesamiento por tipo de escena

**Escenas con mesh estático (Criogenia, OdiseaExterior, Dome_Crio, etc.):**
- Recorrer nodos recursivamente
- Por cada MeshInstance con StaticBody o similar: samplear superficie del mesh a resolución configurable
- CSG nodes (CSGBox, CSGPolygon, etc.) también se samplen

**Props (en todas las escenas):**
- Buscar nodos con grupos `"interactable"`, `"prop"`, `"hazard"`
- También instancias de escenas conocidas (LeakEmitter.tscn, Lever.tscn, PipeValve.tscn, etc.)
- Extraer posición global, AABB, y tag del grupo o nombre
- Todos los props deben aparecer — LeakEmitter, PedestalButton, Lever, PushableBox, PipeValve, SteelPlate, WarningBarrier, DataSlate, BrokenFloorPanel, etc.

**Rotators:**
- Detectar nodos con script CylinderRotator.gd
- Exportar AABB máximo (considerando rotación completa)
- Tag `"rotator"` para que el dashboard los renderice como cilindros wireframe

**Escenas de interior vacías (InteriorLab, InteriorWide, etc.):**
- No exportar geometría — solo metadata: `type: "interior_shell"`
- Se renderizan como caja transparente en el dashboard

### C. Pipeline

```
1. Godot Editor > Tools > Export Scene Geometry
   → tools/export_scene_geometry.gd escanea scenes/levels/ y scenes/reference/
   → genera JSON en exported_scenes/
2. CI (opcional): ejecutar script si hubo cambios en escenas
3. JSON se copian a dashboard/public/scene-data/{scene_name}.json
4. Dashboard los sirve como archivo estático (sin endpoints dinámicos)
```

### D. Dashboard — Three.js consumer

**Nuevo hook:** `useSceneGeometry(sceneName)` — fetch de `scene-data/{sceneName}.json`, cache, parseo.

**Nuevo componente SceneGeometry.tsx:**
- Puntos: `THREE.Points` con material gris acero, tamaño 0.3
- Zonas: `BoxGeometry` wireframe azul tenue
- Props: cajitas small (naranja si interactable, gris si decoration)
- Rotators: cilindros wireframe con animación de rotación continua
- Toggles: `showGeometry`, `showProps`, `showZones`

**Integración en Viewport3D.tsx:**
- SceneGeometry se renderiza dentro del Canvas existente
- Cuando no hay geometría: fallback al grid actual
- Props aparecen con tooltip (nombre al hover)

**Birdseye (LiveMap.tsx):**
- Dibujar contorno de la geometría proyectada en 2D (top-down)
- Props como dots color naranja en el minimapa
- Zonas como rectángulos translúcidos con label

### E. Archivos a crear/modificar

Crear:
- `tools/export_scene_geometry.gd` — script tool Godot 3
- `dashboard/src/hooks/useSceneGeometry.ts` — hook React con fetch + cache
- `dashboard/src/components/SceneGeometry.tsx` — componente Three.js
- `dashboard/src/components/SceneGeometry.css` — estilos (opcional)

Modificar:
- `dashboard/src/components/Viewport3D.tsx` — integrar SceneGeometry
- `dashboard/src/components/LiveMap.tsx` — usar geometría proyectada
- `dashboard/public/scene-data/` — directorio con JSONs generados

Crear rama: `feature/FD-174-scene-geometry`

### F. Lo que NO tocar

- Juego runtime (Godot scenes/scripts de producción)
- ANNAV2 / telemetría
- Hotzone recorder
- Bridge (odisea_central.py)
- CI/CD workflows existentes
- Cualquier archivo fuera de `tools/` y `dashboard/src/`

## Nota sobre procedural (ScaffoldOrbit) — FUTURO

Actualmente fuera de scope. Eventualmente:
1. El script tool recibirá `--seed 42` como parámetro
2. Instanciará ScaffoldStreamController con esa semilla
3. Hará bake del chunk base (forzar generation de chunks alrededor del origen)
4. Exportará la geometría generada

El seed global actual es 42 (definido en ScaffoldStreamController.gd). Es reproducible.
