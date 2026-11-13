# FD-236 — Performance: Hornear AirlockChamber CSG + reducir draw calls en Dome_Crio

## Problema

Telemetría real muestra la celda (0,24) de Dome_Crio a **16 fps / 72% low FPS**. Coincide con `AirlockChamber.tscn`: **9 nodos CSG** generando mesh en runtime + 2 shaders procedurales (`airlock_hull.shader`, `airlock_floor.shader`) + IrisDoorV2 + EmergencyBeaconV2.

El patrón ya se probó con `IrisDoorV2` vía `tools/bake_iris_frame.gd` — hornear CSG a `.mesh` estático es seguro y ya está validado.

## Scope

### 1. Hornear AirlockChamber CSG → .mesh estático

- Crear tool script `tools/bake_airlock_chamber.gd` que:
  - Cargue `AirlockChamber.tscn`
  - Genere `.mesh` combinado de los 9 nodos CSG (CylindricalShell + 3 Ribs + Floor + 3 LightStrips + 2 Conduits)
  - Exporte a `assets/meshes/airlock_chamber_hull.mesh`
- Reemplazar CSG nodes por MeshInstance con el `.mesh` horneado en `AirlockChamber.tscn`
- Mantener colisiones independientes (no hornearlas — usar shapes separadas existentes)
- Verificar que los shaders (hull y floor) siguen aplicándose correctamente al mesh horneado

### 2. Verificar impacto con telemetría

- Celda (0,24) antes: 16 fps / 72% low
- Celda (0,24) después: target > 30 fps
- Comparar draw calls en la celda antes/después usando `perf.dc`

### 3. Opcional: reducir shader cost

Si los shaders procedurales (`airlock_hull.shader`, `airlock_floor.shader`) siguen siendo caros:
- Simplificar complejidad (menos samples, menos capas)
- O hornear las texturas procedurales a `.png` (patrón ya usado en otros props)

## Verificación

- Cargar escena: sin errores, sin CSG en runtime
- Visualmente idéntico (mismo look)
- Celda (0,24) renderea a > 30 fps
- Colisiones funcionan igual (el player atraviesa el airlock normalmente)

## Archivos

| Archivo | Acción |
|---------|--------|
| `core_v2/props/doors/AirlockChamber.tscn` | Reemplazar CSG → MeshInstance |
| `tools/bake_airlock_chamber.gd` | Nuevo — script de bake |
| `assets/meshes/airlock_chamber_hull.mesh` | Nuevo — mesh horneado |

## Out of scope

- No tocar OdiseaExterior
- No modificar la lógica del airlock (AirlockManager)
- No hornear las IrisDoorV2 (ya están horneadas)
