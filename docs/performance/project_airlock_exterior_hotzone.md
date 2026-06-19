# Project Memory: Airlock + Exterior Hotzone

> **Tipo:** `project` (hallazgos para futuras sesiones).
> **Fuente:** `docs/performance/performance_analysis.md` (telemetría ANNAV2 de producción, central :5003, ~562 MB ghosts).
> **Relacionado:** [[project_exterior_perf]], [[project_exterior_clip_through]], [[project_perf_zone_rescan]], [[reference_visualserver_render_info]]

---

## Hallazgos clave

- **Cruzar el airlock cuesta ~8 fps de mediana** (41.3 vs 49.8 global) y **38 % de frames en bajo FPS**. Es **degradación sostenida**, no un hitch de swap de escena. Sesiones desktop nativas (X11/Windows dev) corren a 34–40 fps con 40–48 % de frames lentos mientras cruzan.
- Memoria sube a 65–77 MB en esas sesiones (vs 13–101 MB según escena).

### Dome_Crio (hotzone localizado, no toda la escena)
| grid_x | grid_z | fps | n | % low | nota |
|---:|---:|---:|---:|---:|---|
| 0 | 24 | **16.0** | 1051 | **72 %** | peor punto sostenido |
| 0 | 0 | 37.2 | **5802** | 35 % | celda más transitada del juego |
| 24 | 0 | 39.0 | 1932 | 33 % | corredor +X |
| 16 | 0 | 39.8 | 660 | 29 % | corredor +X |
| 8 | 16 | 58.0 | 4235 | 2 % | celda sana de referencia |

→ El eje **+X (16,0)/(24,0)** forma un *corredor lento* y la celda **(0,24)** es el peor punto. Coincide con la ubicación de `AirlockChamber.tscn` (9 nodos CSG + 2 shaders procedurales + 2× IrisDoorV2). Dome_Crio es la escena más jugada **y** la de mayor memoria (101 MB avg).

### OdiseaExterior (FPS se desploma caminando hacia +X al campo de domos)
| grid_x | grid_z | fps | n | % low | nota |
|---:|---:|---:|---:|---:|---|
| -32 | 0 | 40.1 | 2407 | 1 % | llegada por airlock (SANA) |
| 56 | 0 | 27.3 | 1917 | 35 % | |
| 40 | 0 | 30.7 | 1194 | 51 % | |
| 32 | 0 | 26.2 | 921 | 59 % | |
| 32 | 32 | 9.7 | 606 | 98 % | |

→ La llegada por airlock (-32,0) está **bien**; el FPS se desploma a medida que el jugador camina hacia el **campo de domos (+X)**. Sospechoso #1 = pipeline LOD/streaming de `OdiseaExterior.gd` (`_tick_lod_update_phase`, `PlateContentStream`), no el swap de escena.

### ScaffoldOrbit
- **Despriorizar.** Mediana sana (57.5 fps); sus celdas lentas son puntos de 1–2 muestras (ruido).

---

## Gap de instrumentación (RESUELTO en esta sesión)

`ANNAV2.gd:243-248` ya captura el sub-dict `perf = {dc, obj, vtx, nodes}` en cada heartbeat, pero el central **no lo persistía en la tabla SQLite** `heartbeats` ni lo agregaba en `/ghosts/heatmap` — solo lo guardaba en los JSONL crudos. Por eso sabíamos *dónde* bajaba el FPS pero no *cuántos draw calls/vértices* había por celda.

**Fix aplicado (ver commit / cambios):**
- Tabla `heartbeats` del central: añadidas columnas `draw_calls`, `objects`, `vertices`, `nodes` (ALTER TABLE idempotente, `odisea_central.py:_init_db` + worker INSERT).
- `/ghosts/heatmap`: ahora devuelve `avg_draw_calls`, `avg_objects`, `avg_vertices`, `avg_nodes` por celda.
- `scripts/import_ghosts_to_sqlite.py`: ahora reimporta los JSONL existentes con `perf` (migración retroactiva de la data histórica).

> **Memoria `project_exterior_perf`** ya enseñó que el FPS bajo en el exterior era *draw calls*, no vértices. No asumir — **medir `perf.dc` localizado antes de tocar código.**

---

## Wins candidatos (ordenados por evidencia/impacto)

1. **OdiseaExterior — hotzone +X (investigación profunda, causa reidentificada).**
   - **Hipótesis del pipeline LOD DESCARTADA:** el layout de domes es **estático** (`TerraceSpiral.tscn:animate=false` en todas las espirales → `_is_dome_layout_static()`=true), así que `_bake_all_dome_lod_overlays()` hornea todos los domes una vez y `_dome_lod_baked=true` desactiva el pipeline LOD por-frame (`OdiseaExterior.gd:846` early-returns). El LOD no es la causa del desplome hacia +X.
   - **Hipótesis de acumulación de domos DESCARTADA (medición directa):** `tools/bench_dome_collision_load.gd` confirmó que en OdiseaExterior el modo `set_active_assignments` (direct) está activo el **100 % de las muestras** (`direct_mode_pct: 100`), con **solo 1 slot activo** (`avg_slots_active: 1`) y **1 slot con física** (`avg_slots_with_physics: 1`). El path normal (`_refresh_active_slots` activando 16 slots) **nunca corre** en runtime porque `_direct_active_assignments` se mantiene `true` (solo se resetea a `false` via `assign_scene`/`clear_assignments`, que no se llaman en el exterior). Así que **no hay acumulación de colisiones de domos** — solo el domo de la terraza actual está activo.
   - **Causa reidentificada — costo del domo activo + frecuencia de cambio de plate:** ese único slot contiene **41 CollisionObjects** (`avg_collision_objects_in_slots: 41`). El `DomeFacade_01.tscn` instancia **4 AirlockChamber** completos (North/South/East/West), cada uno con su `AirlockZoneV2` (Area), `CameraWalls` (StaticBody + 3 CollisionShapes), `AirlockSafetyFloor` (StaticBody) y `ChamberZone` (Area) — ~8 CollisionObjects × 4 + la cáscara trimesh del domo = ~33–41. Los 4 AirlockChamber están **siempre activos** (sin `visible=false` ni desactivación), aunque solo 1–2 conecten a terrazas vecinas reales. Al caminar hacia +X el jugador cruza más plates → más cambios de selección → más `set_active_assignments` → más reinstanciación de `DomeFacade` con sus 41 CollisionObjects participando en el broadphase de física.
   - **Pista del desarrollador (confirmada):** `centrifugal_current_plate_only_physics` (PlateContentStream) nunca funcionó bien porque causaba clip-through en terrazas vecinas. **Root cause era el pool del WorldRotator, no los domos:** el BUGFIX en `WorldRotator.gd:335-337` documenta que durante `continuous_tracking` el pool re-center (`_assign_pool_to_nearest_plates`) se saltaba, dejando colliders congelados en plates viejas → el jugador caía al cruzar. Ese bug **ya está fixeado** (el pool ahora se reasigna en ambos modos en el intervalo normal). Por lo tanto reactivar el gating del PlateContentStream hoy **podría** ser seguro, pero no es necesario porque el modo direct ya mantiene solo 1 domo.
   - **✅ WIN APLICADO (esta sesión) — Fix A + Fix B, medido con GPU real (window).**
     - **Fix A:** reactivado `centrifugal_current_plate_only_physics=true` en `OdiseaExterior.tscn` (quitados los 2 overrides `=false` en WorldRotator y PlateContentRoot). El clip-through original NO era del PlateContentStream (domos) sino del pool del WorldRotator, ya fixeado en `WorldRotator.gd:335-337` (el pool re-center ahora corre en ambos modos). El modo direct (`set_active_assignments`, 100% del tiempo) ya mantiene solo 1 domo activo, así que el gating no afecta los slots — afecta el pool de terrazas del rotator.
     - **Fix B:** neutralizadas las colisiones redundantes de los 4 AirlockChamber en `DomeFacade_01.tscn` (override `collision_layer=0, collision_mask=0` en `ChamberZone`, `AirlockSafetyFloor`, `CameraWalls` de cada airlock). Esos StaticBodies/Areas son redundantes en el contexto exterior: la terraza (pool del WorldRotator, BoxShape) ya provee el piso, el jugador nunca camina dentro del corredor del chamber hasta entrar al interior, y los CameraWalls (collision_mask=0) solo servían para camera-clip en interiores. Las `AirlockZoneV2` (Areas de detección de entrada) se preservan intactas. El `AirlockChamber.tscn` base (usado standalone en Dome_Crio) **no** fue modificado — solo el DomeFacade.
     - **Resultados A/B con GPU real (window 640×360, uncapped):**

       | Métrica | Baseline | Fix A (gating) | Fix A+B | Delta total |
       |---|---:|---:|---:|---:|
       | draw_calls | 1673 | 813 | **841** | **−832 (−50 %)** |
       | avg_fps | 309 | 296 | **407** | **+98 (+32 %)** |
       | min_fps | 61 | 29 | **54** | −7 |
       | frames_lt30 | 0 | 26 | **0** | 0 (mejoró vs Fix A solo) |
       | node_count | 568 | 560 | 560 | −8 |

     - Fix A solo bajó draw_calls de 1673→813 pero introdujo 26 frames < 30fps (hitch durante transiciones de plate). **Fix B compensó ese hitch**: frames_lt30 volvió a 0 y avg_fps subió a 407 (+32 % vs baseline). El hitch de Fix A venía del broadphase churn durante reactivación de física de slots — Fix B redujo los CollisionObjects de 41 → ~11 por domo, eliminando el churn.
     - **Validación visual con GPU:** exterior renderiza correctamente (screenshot 99.9 % non-black, mean luminance 37.2). Door interaction funciona (logs: `IrisMechanism set_active(True)` al INTERACT). Sin warnings de clip-through/floor_contact en 600 frames de gameplay. Dome_Crio sin regresiones (draw_calls 210→194, 0 frames < 30).
2. **Dome_Crio celda (0,24) @ 16 fps / 72 % low y corredor +X (16,0)/(24,0).** Localizar qué props/geometría caen en esas celdas (probablemente AirlockChamber + CSG/shaders + IrisDoorV2). Comparar `perf.dc` de (0,24) vs (8,16).
3. **AirlockChamber — hornear CSG a .mesh/.shape.** ✅ **APLICADO (esta sesión).** Patrón ya probado (`IrisDoorV2` horneado vía `tools/bake_iris_frame.gd`). Reemplazados los **9 nodos CSG** del chamber por **10 ArrayMesh estáticos** + StaticBody/CollisionShape. Verificación estructural PASS (`tools/verify_airlock_baked.gd`: 0 CSG restantes, 33 MeshInstances, 28 materials válidos, ShaderMaterial del hull preservado, collision shape válida). Microbenchmark A/B (`tools/bench_airlock_csg_cost.gd`): **CSG build cost: 0.008 ms → 0 ms** (10 nodos CSG → 0). **Baseline de producción del hotzone (0,24) @ 16 fps / 72 % low** es el síntoma a re-medir en GPU real post-deploy; el costo CSG rebuild por frame (no capturable en headless) es lo que el bake elimina. Shaders procedurales (`airlock_hull.shader`, `airlock_floor.shader`) siguen corriendo por píxel (preservados en los meshes) — el bake solo elimina el rebuild de geometría, no el costo de shader. Archivos: `tools/bake_airlock_chamber.gd`, `tools/bench_airlock_csg_cost.gd`, `tools/verify_airlock_baked.gd`, `core_v2/props/doors/airlock_baked/*.mesh/.shape`, `core_v2/props/doors/AirlockChamber.tscn`.
4. **Instanciación síncrona en el swap (`SceneManager.gd:195`).** Pico del freeze al cruzar. Menor prioridad que la degradación sostenida, pero medible.
5. **WorldRotator sync por frame (`:1782`) y push de RigidBodies por frame (`PlayerControllerV2.gd:2239`).** Costos por frame del player; revisar si contribuyen al corredor lento del exterior.
6. **Memoria Dome_Crio = 101 MB (la más alta).** No es FPS directo pero correlaciona con GC y carga.

**Despriorizar:** ScaffoldOrbit (sano de mediana), WFC threading (sin señal de hotzone), GLES2 GPU-Particles rotos (`plasma_particles.tscn`, `FireEmitter.tscn` — bug de correctitud, no de perf de hotzone).

---

## Archivos clave (referencia)
- `core_v2/levels/OdiseaExterior.gd` — pipeline LOD/streaming (sospechoso #1)
- `core_v2/levels/interiors/Dome_Crio.tscn` — interior con el corredor hotzone
- `core_v2/props/doors/AirlockChamber.tscn` — 9 CSG + 2 shaders (candidato a hornear)
- `core_v2/autoloads/SceneManager.gd:195` — instanciación síncrona (pico de swap)
- `core_v2/autoloads/AirlockManager.gd:96-165` — seamless swap
- `core_v2/player/PlayerControllerV2.gd` — step(), snap, push RigidBody
- `core_v2/systems/WorldRotator.gd:1782` — sync de pool por frame
- `core_v2/telemetry/ANNAV2.gd:243-248` — `perf` sub-dict (capturado; ahora persistido)
- `odisea_central.py` (`handle_ghosts_heatmap/stats/sessions`, `_init_db`, worker INSERT) — fuente/almacenaje de la telemetría
- `scripts/import_ghosts_to_sqlite.py` — reimport de JSONL históricos

## Notas operativas
- `low_fps_threshold = 30` (definido en `odisea_central.py:handle_ghosts_heatmap`).
- La DB local `data/ghosts.db` es **solo data sintética de test (60 fps constante)** — ignorarla. La data real vive en el central :5003.
- `odisea_central.py` persiste el heartbeat completo en JSONL (`_store_ghost:2862-2884`) — ahí el `perf` SI estaba, pero la tabla SQLite no lo indexaba.
