# Análisis de Performance: Airlock + Domo Exterior (Odisea)

> **Entregable:** este documento es un **análisis** (no contiene fixes). Su objetivo es
> darle a un agente frontera una base sólida, respaldada por telemetría ANNAv2 de
> producción, para empezar a optimizar. Prioridad: lo que rodea al **Airlock** y al
> **Domo Exterior**, que es donde el heatmap muestra los hotzones.

---

## Context

El usuario reporta que al **entrar y atravesar el Airlock** el juego se pone lento. Pidió
una evaluación del funcionamiento y una descripción de lo implementado en Dome_Crio,
OdiseaExterior y ScaffoldOrbit (más PlayerController y props), usando telemetría ANNAv2,
para localizar *wins* de performance alrededor del Airlock y del Domo Exterior.

La telemetría confirma el reporte y lo cuantifica: **atravesar el airlock cuesta ~8 fps de
mediana y triplica los frames en bajo FPS**. No es un hitch de un frame al cargar escena —
es una **degradación sostenida** mientras el jugador está en zonas concretas.

---

## Evidencia de telemetría (producción, central :5003, ghosts ~562 MB)

Fuente: `/ghosts/stats`, `/ghosts/sessions`, `/ghosts/heatmap` del nodo central. La DB
local `data/ghosts.db` es **solo data sintética de test (60 fps constante)** — ignorarla.
`low_fps_threshold = 30` (definido en `odisea_central.py:handle_ghosts_heatmap`).

### Por escena (volumen de juego real)
| Escena | ghosts | sessions | mem_avg MB | mediana fps celda |
|---|---:|---:|---:|---:|
| **Dome_Crio** | 37 838 | 244 | **101.0** | 49.9 |
| **ScaffoldOrbit** | 28 179 | 62 | 13.7 | 57.5 |
| **OdiseaExterior** | 17 310 | 198 | 65.2 | **29.0** |

- Dome_Crio es la escena más jugada **y** la de mayor memoria (101 MB avg).
- OdiseaExterior tiene **mediana de celda en 29 fps** (justo en el umbral de bajo FPS): es
  la escena estructuralmente más pesada.
- ScaffoldOrbit está **sana de mediana** (57.5 fps); sus celdas lentas son puntos de 1–2
  muestras (ruido, no hotzone). **Despriorizar ScaffoldOrbit.**

### Costo de atravesar el airlock (sesiones que visitan interior **y** exterior)
- 50 de 200 sesiones cruzan el airlock.
- **Mediana avg_fps cruzando = 41.3 | media low_fps_pct = 38.3 %**
- Mediana avg_fps de todas las sesiones (fps>5) = 49.8
- Sesiones desktop nativas (X11/Windows dev) cruzando: **34–40 fps con 40–48 % de frames
  en bajo FPS** → sostenido, no un pico aislado.
- Memoria en esas sesiones sube a 65–77 MB.

### Localización del hotzone (heatmap, resolution=8, grid_x/grid_z)
**Dome_Crio** (el hotzone es localizado, no toda la escena):
| grid_x | grid_z | avg_fps | n (muestras) | % low |
|---:|---:|---:|---:|---:|
| 0 | 24 | **16.0** | 1051 | **72 %** |
| 0 | 0 | 37.2 | **5802** (la celda más transitada del juego) | 35 % |
| 24 | 0 | 39.0 | 1932 | 33 % |
| 16 | 0 | 39.8 | 660 | 29 % |
| 8 | 16 | 58.0 | 4235 | 2 % ← celda sana de referencia |

→ El eje **+X (16,0)/(24,0)** forma un *corredor lento* y la celda **(0,24)** es el peor
punto sostenido. Contrastan con (8,16) a 58 fps: **la lentitud está concentrada en zonas
con alta densidad de draw calls / props, probablemente el corredor del airlock y el área
central de spawn.**

**OdiseaExterior** (alta población a lo largo de +X, alejándose del airlock):
| grid_x | grid_z | avg_fps | n | % low |
|---:|---:|---:|---:|---:|
| -32 | 0 | 40.1 | 2407 | 1 % ← celda de llegada por airlock (sana) |
| 56 | 0 | 27.3 | 1917 | 35 % |
| 40 | 0 | 30.7 | 1194 | 51 % |
| 32 | 0 | 26.2 | 921 | 59 % |
| 32 | 32 | 9.7 | 606 | 98 % |

→ La llegada por airlock (-32,0) está **bien**; el FPS se desploma a medida que el jugador
**camina hacia el campo de domos (+X)**. Esto apunta directo al **pipeline LOD/streaming de
domos** de `OdiseaExterior.gd`, no al swap de escena en sí.

---

## Cómo funciona lo implementado (mapa del sistema)

### Transición por Airlock (seamless swap — FD-053)
- `AirlockManager.gd` (autoload): al cruzar la zona, reparenta al player a
  `/root/AirlockManager`, destruye la escena vieja, carga la nueva, y reparenta de vuelta
  (`AirlockManager.gd:96-165`). Mantiene la cámara sin frame negro.
- `SceneManager.gd`: carga con `ResourceLoader.load_interactive` (budget 6/10/14 ms por
  frame según hardware, `SceneManager.gd:11-13,159-181`), pero la **instanciación es
  síncrona**: `resource.instance()` en `SceneManager.gd:195` crea todos los nodos en un
  frame → pico de CPU/alloc en escenas grandes.
- Props pesados se difieren al grupo `deferred_build` y se construyen un nodo por frame
  (`SceneManager.gd:248-271`) — el comentario confirma que el *bulk instancing* es "el
  freeze que se siente en la transición".
- **Conclusión telemétrica:** el swap es un *pico*, pero el reporte del usuario y los datos
  (low_fps sostenido, no un solo frame) indican que el problema dominante es lo que pasa
  **después** del swap: la escena destino corriendo en el corredor del airlock / campo de domos.

### OdiseaExterior — pipeline LOD/streaming (el sospechoso #1 del exterior)
`OdiseaExterior.gd` (~1875 líneas). Por frame en `_process()` (`OdiseaExterior.gd:190-206`):
- `_tick_airlock_chamber_gate()` — si el player está en el airlock, **throttlea** todo el
  pipeline (`if _airlock_streaming_throttled: return`, `:193`). Bien: explica por qué la
  celda de llegada (-32,0) está sana.
- `_tick_dome_assignment_cache_build()` — construye incrementalmente la cache de asignación
  de **596 plates** con blueprints LOD (budget 2 ms/frame, `:415-533`).
- `_tick_lod_update_phase()` — al rotar la cámara > umbral (20°), snapshot de orígenes +
  sort O(k log k) con penalización de frustum + flush a MultiMesh (`:843-947`).
- `PlateContentStream._physics_process()` — sincroniza slots/física por frame (`:49-78`).
- Facades: `DomeFacadeFD_merged.mesh` ya está optimizado (691 surfaces → 1, 9× menos draw
  calls — ver memoria `project_exterior_perf`). MultiMesh batchea 128 domos/draw.

### Dome_Crio — interior
`Dome_Crio.tscn` (1463 líneas). Geometría Qodot (.map) + props instanciados:
ScaffoldWalkway, **AirlockChamber**, FloorHatch, CriopodParallax, SteelGratePlatform,
SciFiWorkLightTripodV2, MaintenanceElevator, etc. 1 OmniLight ambiental, sin GI/baked
lightmaps, sin partículas en la escena base.

### AirlockChamber — el prop del hotzone
`AirlockChamber.tscn`: **9 nodos CSG** que generan mesh en runtime (CylindricalShell +
3 Ribs CSGTorus + Floor + 3 LightStrips + 2 Conduits), **2 shaders procedurales**
(`airlock_hull.shader` con rivets/seams/wear, `airlock_floor.shader` con grid/tread) y
**2× IrisDoorV2 + 1× EmergencyBeaconV2**. Sin OmniLight propio (brillo por emisión).
→ Coincide con el corredor lento del eje +X en Dome_Crio.

### PlayerController y física
`PlayerControllerV2.gd` (~2600 líneas):
- `step()` por frame: movimiento, `move_and_slide_with_snap` (`:2218`), push de RigidBodies
  iterando `get_slide_count()` cada frame (`:2239-2256`).
- Snap de suelo: `snap_length=0.25`, sube a `moving_floor_snap_length=2.0` sobre terraza
  móvil (`:31-39,2196-2218`) — anti clip-through (memoria `project_exterior_clip_through`).
- Scans throttleados: zonas de cámara `% 16` (`:2350`), interactables `% 8` (`:1592`).
- `WorldRotator.gd`: pool fijo de 32 StaticBodies, reasignado cada 3 frames pero
  **sincronizado cada frame** (`:1782`) — "pool per-frame disparó CPU" (memoria).
- `CameraZoneV2`/`CameraZone.gd`: scan de grupo throttleado (memoria `project_perf_zone_rescan`).

### Telemetría ANNAv2 (lo que YA capturamos y lo que falta)
`ANNAV2.gd` emite heartbeat 10 Hz (`:172-187`). Campos: position, velocity, yaw/pitch/roll,
scene, zone, fps, memory_mb, **y un sub-dict `perf` con `dc` (draw calls), `obj`, `vtx`,
`nodes`** (`ANNAV2.gd:238-243`).
**Gap crítico:** el `perf` sub-dict **no se persiste en los ghosts del central** — la tabla
solo guarda fps/mem/pos (ver `import_ghosts_to_sqlite.py` / schema de `ghosts.db`). Por eso
sabemos *dónde* baja el FPS pero no *cuántos draw calls/vértices* hay en cada celda. Para el
agente frontera, **capturar `perf.dc/vtx/obj` localizado es el primer paso de instrumentación.**

---

## Wins de performance candidatos (para que el agente frontera priorice)

Ordenados por evidencia/impacto. **Verificar cada uno con `perf.dc/vtx` localizado antes de
tocar código** — la memoria `project_exterior_perf` enseña que el FPS bajo era *draw calls*,
no vértices; no asumir.

1. **OdiseaExterior — pipeline LOD del campo de domos (+X).** Las celdas (32–56, 0) a
   26–31 fps con 35–59 % low son el peor hotzone por población. Investigar: ¿el LOD update
   (`_tick_lod_update_phase`) o el draw-call count de los domos cercanos escala mal al
   caminar hacia +X? ¿`PlateContentStream` activa física de más plates? Medir `perf.dc` por
   celda. **Mayor win potencial.**

2. **Dome_Crio celda (0,24) @ 16 fps / 72 % low y corredor +X (16,0)/(24,0).** Localizar qué
   props/geometría caen en esas celdas (probablemente AirlockChamber + sus CSG/shaders +
   IrisDoorV2). Candidatos: ¿9 nodos CSG re-bakeando?, shaders procedurales caros por píxel,
   draw calls de props no instanciados. Comparar `perf.dc` de (0,24) vs la celda sana (8,16).

3. **AirlockChamber — hornear CSG a .mesh/.shape.** Patrón ya probado en el proyecto
   (`IrisDoorV2` se horneó vía `tools/bake_iris_frame.gd`, memoria `project_fd224_idle_culling`).
   9 nodos CSG por chamber generando mesh en runtime es un costo evitable.

4. **Instanciación síncrona en el swap (`SceneManager.gd:195`).** Es el *pico* del freeze al
   cruzar. Menor prioridad que la degradación sostenida, pero medible: cronometrar
   `resource.instance()` para Dome_Crio vs OdiseaExterior.

5. **WorldRotator sync por frame (`:1782`) y push de RigidBodies por frame
   (`PlayerControllerV2.gd:2239`).** Costos por frame del player; revisar si contribuyen al
   corredor lento del exterior.

6. **Memoria Dome_Crio = 101 MB (la más alta).** No es FPS directo pero correlaciona con GC
   y carga; investigar qué retiene tanto (¿texturas de props, meshes CSG, cache de domos?).

**Despriorizar:** ScaffoldOrbit (sano de mediana), el WFC threading (sin señal de hotzone),
GLES2 GPU-Particles rotos (`plasma_particles.tscn`, `FireEmitter.tscn` — bug de correctitud,
no de perf de hotzone).

---

## Verificación / instrumentación recomendada (para el agente frontera)

1. **Capturar `perf` localizado.** Correr local con `godot3-bin` + peer bridge (:4999) y
   atravesar el airlock caminando hacia +X en ambas escenas. Vía `/eval` o el ring buffer de
   captura de `ANNAV2.gd`, registrar `perf.dc/vtx/obj` junto a `position` para construir un
   heatmap de **draw calls** (no solo fps). Comando base:
   `curl "localhost:4999/eval?expr=Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)"`.
2. **Perfilar con VisualServer render_info** (memoria `reference_visualserver_render_info`:
   usar `INFO_OBJECTS_IN_FRAME` + `INFO_2D_ITEMS_IN_FRAME`; las constantes `*_DRAWS_IN_FRAME`
   no existen en 3.6).
3. **Reproducir el cruce** con `/command/batch` (teleport → screenshot → inspect_node) para
   un repro determinista de cada celda hotzone.
4. **Comparar antes/después** con las mismas celdas del heatmap (`/ghosts/heatmap?scene=...`)
   una vez que haya tráfico real post-fix.

## Acción al ejecutar: guardar memoria de proyecto
Crear un memory file `project_airlock_exterior_hotzone.md` (tipo `project`) con los hallazgos
clave para futuras sesiones, y agregar su línea al `MEMORY.md`:
- Cruzar airlock cuesta ~8 fps mediana (41.3 vs 49.8) y 38 % de frames en bajo FPS;
  degradación **sostenida**, no hitch de swap.
- Dome_Crio hotzones: celda (0,24) @ 16 fps/72 % low, corredor +X (16,0)/(24,0) @ ~39 fps;
  celda (0,0) es la más transitada (5802 muestras) @ 37 fps. Celda sana de ref: (8,16) @ 58.
- OdiseaExterior: llegada por airlock (-32,0) sana @ 40 fps; FPS se desploma caminando hacia
  +X al campo de domos (32–56,0 @ 26–31 fps) → sospechoso = pipeline LOD `OdiseaExterior.gd`.
- ScaffoldOrbit sano (mediana 57.5) → despriorizar.
- **Gap:** `perf.dc/vtx/obj` se captura en `ANNAV2.gd` pero NO se persiste en los ghosts del
  central → no hay heatmap de draw calls; instrumentar eso es el paso 1 del agente frontera.
- `data/ghosts.db` local es data de test (60 fps constante); la data real vive en central :5003.
- Enlazar con [[project_exterior_perf]], [[project_exterior_clip_through]],
  [[project_perf_zone_rescan]], [[reference_visualserver_render_info]].

## Archivos clave (referencia)
- `core_v2/levels/OdiseaExterior.gd` — pipeline LOD/streaming (sospechoso #1)
- `core_v2/levels/interiors/Dome_Crio.tscn` — interior con el corredor hotzone
- `core_v2/props/doors/AirlockChamber.tscn` — 9 CSG + 2 shaders (candidato a hornear)
- `core_v2/autoloads/SceneManager.gd:195` — instanciación síncrona (pico de swap)
- `core_v2/autoloads/AirlockManager.gd:96-165` — seamless swap
- `core_v2/player/PlayerControllerV2.gd` — step(), snap, push RigidBody
- `core_v2/systems/WorldRotator.gd:1782` — sync de pool por frame
- `core_v2/anna/v2/ANNAV2.gd:238-243` — `perf` sub-dict (capturado pero NO persistido en ghosts)
- `odisea_central.py` (`handle_ghosts_heatmap/stats/sessions`) — fuente de la telemetría
