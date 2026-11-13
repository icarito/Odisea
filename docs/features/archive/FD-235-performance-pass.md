# FD-235 — Performance Pass: OdiseaExterior + Dome_Crio + ScaffoldOrbit

## Problema

Telemetría real de producción (ghosts, central :5003, 132k heartbeats en 1481 sesiones) muestra 3 hotzones de performance que degradan el VS:

| Escena | Mediana FPS | Memoria | Peor celda |
|--------|------------|---------|------------|
| OdiseaExterior | **29.0** | 65 MB | (32,32) → 9.7 fps / 98% low |
| Dome_Crio | 49.9 | **101 MB** | (0,24) → 16 fps / 72% low |
| ScaffoldOrbit | 57.5 | 13.7 MB | sano |

- Cruzar el airlock cuesta ~8 fps de mediana y 38% de frames en bajo FPS
- El FPS se desploma al caminar hacia +X en OdiseaExterior (campo de domos)
- Dome_Crio tiene un corredor lento en +X (celdas 16,0/24,0 a ~39 fps)

## Scope

### 1. Instrumentación — persistir `perf.dc/vtx/obj` en ghosts

`ANNAV2.gd:238-243` ya captura `perf` (draw calls, objetos, vértices) pero NO se persiste en la tabla `ghosts` del central. Sin esto no hay heatmap de draw calls.

- Modificar `ANNAV2.gd` para incluir `perf.dc`, `perf.vtx`, `perf.obj` en el payload del heartbeat
- Modificar `odisea_central.py` para persistir los campos `dc`, `vtx`, `obj` en `ghosts`
- Verificar que `/ghosts/heatmap?scene=...` puede filtrar por draw calls

### 2. OdiseaExterior — optimizar pipeline LOD del campo de domos

El sospechoso #1 del exterior: `OdiseaExterior.gd` (~1875 líneas). Las celdas +X (32-56,0) bajan a 26-31 fps.

**Hallazgos del análisis:**
- `_tick_dome_assignment_cache_build()` maneja 596 plates con LOD (budget 2 ms/frame)
- `_tick_lod_update_phase()` hace sort O(k log k) + frustum penalty + flush a MultiMesh
- `PlateContentStream` sincroniza slots/física por frame
- La llegada por airlock (-32,0) está sana porque `_tick_airlock_chamber_gate()` throttlea el pipeline

**Acciones:**
- Medir `perf.dc` por celda al caminar hacia +X (instrumentación del punto 1)
- Investigar throttling o budget del LOD update en las celdas +X
- Revisar si `PlateContentStream` activa física de más plates de los necesarios
- Verificar que MultiMesh batch size (128 domos/draw) es óptimo

### 3. Dome_Crio — hornear AirlockChamber CSG → mesh

El hotzone (0,24) a 16 fps coincide con AirlockChamber: 9 nodos CSG generando mesh en runtime + 2 shaders procedurales. Patrón ya probado: `IrisDoorV2` se horneó vía `tools/bake_iris_frame.gd`.

- Hornear `AirlockChamber.tscn` CSG a `.mesh` estático
- Reemplazar CSG nodes por MeshInstance con el mesh horneado
- Mantener colisiones con shapes separadas
- Verificar FPS en celda (0,24) antes/después con telemetría

### 4. SceneManager — instanciación síncrona en swap

`SceneManager.gd:195`: `resource.instance()` crea todos los nodos en un frame → pico de CPU al cruzar. Props pesados ya se difieren (`deferred_build`), pero la instanciación base sigue siendo síncrona.

- Perfilar el tiempo de `resource.instance()` para Dome_Crio y OdiseaExterior
- Si > 16ms: diferir la instanciación en chunks (n nodos por frame)
- Prioridad media: es un pico, no la degradación sostenida

### 5. WorldRotator — reducir sync por frame

`WorldRotator.gd:1782`: pool de 32 StaticBodies sincronizado cada frame, y push de RigidBodies por frame en `PlayerControllerV2.gd:2239`.

- Revisar si la sync se puede throttlear (ya hay patrón de throttle en otros sistemas)
- Medir costo CPU de `get_slide_count()` + iteración de RigidBodies en el player

### 6. Memoria Dome_Crio — 101 MB

No es FPS directo pero correlaciona con GC y carga.

- Identificar qué retiene más memoria (texturas de props, meshes CSG, cache)
- Revisar `resource_local_to_scene` en texturas de props repetidos
- Verificar que recursos se liberan al salir de la escena

## Despriorizado

- **ScaffoldOrbit** — sano de mediana (57.5 fps)
- **WFC threading** — sin señal de hotzone
- **GLES2 GPU-Particles** — bug de correctitud, no de perf

## Archivos

| Archivo | Acción |
|---------|--------|
| `core_v2/anna/v2/ANNAV2.gd` | Añadir perf.dc/vtx/obj al heartbeat |
| `odisea_central.py` | Persistir dc/vtx/obj en ghosts |
| `core_v2/levels/OdiseaExterior.gd` | Optimizar LOD pipeline |
| `core_v2/props/doors/AirlockChamber.tscn` | Hornear CSG → mesh |
| `core_v2/autoloads/SceneManager.gd` | Diferir instanciación |
| `core_v2/systems/WorldRotator.gd` | Throttlear sync |
| `core_v2/player/PlayerControllerV2.gd` | Revisar push RigidBody |

## Verificación

- Heatmap de draw calls por celda usando `/ghosts/heatmap` con los nuevos campos
- Antes/después: misma ruta (cruzar airlock, caminar hacia +X) en ambas escenas
- Celda (0,24) Dome_Crio: target > 30 fps (> 50% mejora vs 16 fps actual)
- Celdas +X OdiseaExterior: target > 35 fps (> 20% mejora vs 26-31 fps actual)
- Memoria Dome_Crio: target < 80 MB (reducción 20% vs 101 MB)

## Referencias

- `docs/performance/performance_analysis.md` — análisis completo con telemetría
- `docs/features/FD-224-perf-code-review.md` — low hanging fruit previos
- `docs/performance/perf_lab_2026-02-22.md` — benchmarks históricos
