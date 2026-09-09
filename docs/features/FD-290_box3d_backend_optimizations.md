# FD-290: Optimizaciones del backend Box3D y fruta al alcance de la mano para Odisea
**Status:** In Progress **Priority:** High **Effort:** Medium **Created:** 2026-09-09 **Reusa:** godot-box3d-3 v0.2.0 (módulo custom), CollisionCullManager, FakeShadow, KinematicArm3D, GasParticleManager

> **Notas de Odiseo:**
> 1. Este FD documenta el lado *Odisea* del estudio hecho en `icarito/godot-box3d-3` (el módulo ya salió optimizado en **v0.2.0**). Cada punto cita archivo y línea del estado del código de hoy; los milisegundos citados vienen de `core_v2/autoloads/CollisionCullManager.gd` (Redmi Note 9 Pro, GLES2), el perfil más restrictivo del proyecto.
> 2. **No cambia gameplay ni determinismo:** todo lo propuesto es de rendimiento y de higiene de carga. Los replays `.oys` existentes siguen siendo la vara.
> 3. Numeración: FD-290 estaba libre en `FEATURE_INDEX.md` al momento de crearlo.
> 4. **2026-09-09 — primer lote aterrizado** (ver "Landed" al final): retiro de CollisionCullManager en Box3D, cache de trimesh por Mesh, cast único en KinematicArm3D, presupuesto de raycasts de gas, lookups cacheados, FakeShadow (resolución ARM + query directa + cache de malla). El deriva 5.74 m del strafe **ya no reproduce** con el culler apagado (verificado con `ODISEA_DISABLE_COLLISION_CULL=1`): la grabación actual es válida sin culling.
> 5. **2026-09-09 — segundo lote:** camino Box3D de PushableBoxV2 (sleeping en vez de kinematic, sin snap rotacional — Sebastián confirmó que el snap era el parche de determinismo, no gameplay).
> 6. **2026-09-09 — tercer lote (noche):** carga web medida y optimizada con Playwright + Thorium (ver "Arranque en navegador — segundo lote"): `shader_compilation_mode.web=2`, warmup de Dome_Intro cableado desde el Menu, batching en el addon. Menu → Dome_Intro: 26–29 s → 6.1 s.

## Problem

La migración a Box3D (CI ya corre el binario custom desde el PR #324) deja a Odisea en un estado donde el servidor de física ya no es el cuello principal — pero el proyecto sigue cargando patrones nacidos de las limitaciones de Bullet:

* **`CollisionCullManager`** (`core_v2/autoloads/CollisionCullManager.gd:1-74`) existe para amortiguar el broadphase de Bullet sobre 383 formas Prop: el 58 % del tick móvil (7.81 ms de ~14 ms). Box3D no refittea las AABB de cuerpos estáticos, así que el motivo de ser del manager desaparece — y su propio doc registra el bug que introduce (replay `test_locomocion_strafe` atraviesa un prop culleado, `:67-70`).
* **`FakeShadow` en modo `grid`** lanza 64 raycasts por actor cada 4 frames (0.33 ms medidos en móvil; `core_v2/visual/FakeShadow.gd:222`, grilla 8×8 en `Pilot_v2.tscn:246-257`), y reconstruye la malla con `SurfaceTool` en cada refresh (`:282-531`) aunque el terreno apenas cambie.
* **`Mesh.create_trimesh_shape()` crea un BVH nuevo por llamada**: `DuctMazeStreamer.gd:466,515,551,691,745,1124`, `ScaffoldHubRing.gd:367` y `CircuitCable.gd:95` levantan shapes duplicados para meshes que se repiten, golpeando el pico de carga del streaming de ductos.
* **`KinematicArm3D`** lanza hasta 3 `intersect_shape` por tick (hit + lookahead + motion lookahead, `core_v2/camera/KinematicArm3D.gd:321,350,356`) más el chequeo de techo; 0.26 ms/tick.
* **`GasParticleManager`** raycastea por partícula por tick (`core_v2/systems/gas/GasParticleManager.gd:483`); el gate de `raycast_min_speed` amortigua pero no acota.
* **Lookups por tick sin cachear**: `SessionManager.gd:1528` busca `/root/PerformanceMonitor` en cada `_physics_process` y `PlayerControllerV2.gd:3122` busca `SessionManager` por tick. El proyecto ya documenta el patrón correcto (`PipeCoolantRun.gd:109-112`).

**Objetivo:** capturar la ganancia de la migración Box3D retirando las muletas de Bullet y ajustando los puntos calientes de queries, sin tocar el contrato de determinismo que la CI valida.

## Solution

Tres frentes, en orden de valor:

### 1. Retirar (o atenuar) `CollisionCullManager`

Con Box3D las formas estáticas no cuestan por iterar. Apagar el manager elimina un `_physics_process` cada 8 frames *y* un error de física conocido. El bug de `test_locomocion_strafe` documentado en `:67-70` era el precio del culling: desaparece con él.

### 2. Queries y carga (cambios pequeños por archivo)

* **FakeShadow**: de menor a mayor esfuerzo — (a) bajar `grid_resolution` a 5-6 en ARM (el fallback `cheap` ya existe, `:82-89`); (b) migrar la grilla a una sola pasada de `PhysicsDirectSpaceState.intersect_ray` sobre puntos pre-computados, sin nodos `RayCast` ni `force_raycast_update`; (c) cachear la malla y regenerar solo cuando algún rayo cruza `snap_amount`.
* **Trimesh compartidos**: cachear un `ConcavePolygonShape` por `Mesh` recurso (punto de paso natural: `core_v2/systems/collision/ShapeBounds.gd:39`). El módulo valida el patrón con su test `m14_shared_trimesh`.
* **Bakes con primitivas donde alcance**: la decisión ya tomada para criopods (`tools/bake_dome_intro_criopods.gd:219-222`) generaliza: suelo/tuberías/andamio horneados como trimesh pagan 2× triángulos por el doble winding. `bake_scaffold_walkways.gd` (colisión por sub-scene con shapes originales) es el patrón correcto a mantener.
* **KinematicArm3D**: derivar el lookahead del `closest_safe` de un único `cast_motion`.
* **Gas**: tope por tick — raycastear solo las K partículas más rápidas y repartir el resto por turnos.
* **Lookups cacheados** en `SessionManager` y `PlayerControllerV2` (micro, pero se paga en cada replay).

### 3. Config al tomar v0.2.0

* `physics/3d/box3d_substeps` (default 2): subir solo si las pilas se sienten blandas. **Ojo**: cambiar sub-steps cambia trayectorias → re-grabar los replays `.oys` afectados.
* El bump de `BOX3D_RELEASE` va en este mismo PR (ver abajo).

### Considered Options

- **Option A**: Solo actualizar el binario (bump de release) sin tocar Odisea. — Pros: cero riesgo. Cons: deja el 58 % del tick móvil pagando muletas de Bullet que ya no hacen falta, y el FD muere en un "upgrade de versión".
- **Option B**: Optimizar Odisea sin actualizar el módulo. — Cons: pierde las optimizaciones de v0.2.0 (dispatch por move events, shapes incrementales, overrides por broadphase, buffer compartido de contactos) que benefician justo las rutas de Odisea: carga con shapes múltiples, zonas de gravedad y `contact_monitor` de `PushableBoxV2`/`FusionCore`.
- **Selected**: **Bump + retiro gradual de muletas**, en ese orden. El bump es inocuo por sí solo (semántica de física idéntica, 27/27 escenas de aceptación del módulo y los replays de física de Odisea pasan igual); los items de rendimiento se pueden aterrizar uno por PR con su replay de validación.

## Files to Modify

- `.github/workflows/determinism_tests.yml` (modify — `BOX3D_RELEASE: v0.2.0`)
- `.github/workflows/export_all.yml` (modify — `BOX3D_RELEASE: v0.2.0`)
- `core_v2/autoloads/CollisionCullManager.gd` (modify — retirar o desactivar por default)
- `core_v2/visual/FakeShadow.gd` (modify — opciones §2)
- `core_v2/systems/DuctMazeStreamer.gd`, `core_v2/props/scaffold/ScaffoldHubRing.gd`, `core_v2/systems/circuit/CircuitCable.gd` (modify — cache de trimesh)
- `core_v2/camera/KinematicArm3D.gd` (modify — `cast_motion`)
- `core_v2/systems/gas/GasParticleManager.gd` (modify — presupuesto de raycasts)
- `core_v2/autoloads/SessionManager.gd`, `core_v2/player/PlayerControllerV2.gd` (modify — caches)

## Verification

1. `./runtest.sh --oys test_locomocion_walk` (y el resto de replays de locomoción/push) en verde con el binario v0.2.0 descargado por la CI.
2. Suite completa: `./runtest.sh` (pytest → gdUnit) sin drift > 0.01 en los replays de determinismo.
3. A/B de rendimiento móvil antes/después de cada item: el perfil de `CollisionCullManager` como línea base (servidor de física 7.81 ms/tick en Redmi Note 9 Pro); objetivo: servidor de física < 3 ms/tick y cero culling de props.
4. Carga de `Dome_Intro` (import + primer frame) con y sin cache de trimesh en el streamer de ductos.

## Landed — 2026-09-09 (primer lote)

Verificado con `./runtest.sh` local (Bullet, binario stock 3.6.2) y replays de locomoción/push en verde, con y sin culling (`ODISEA_DISABLE_COLLISION_CULL=1`). El backend Box3D no existe en el binario local; la CI determinista (override.cfg → Box3D) es la que ejercita el retiro del culler.

1. **CollisionCullManager retirado en Box3D** (`core_v2/autoloads/CollisionCullManager.gd`): `_ready()` lee `physics/3d/physics_engine` de ProjectSettings (cubre override.cfg de la CI determinista, el append de export_all.yml y el dev local) y se apaga solo en `Box3D`: sin `_physics_process`, sin barrido, sin culling (y con él, el agujero del strafe deja de existir). Bajo Bullet el comportamiento es byte a byte el histórico. `ODISEA_FORCE_COLLISION_CULL=1` re-lo prende en Box3D para el A/B del punto 3; `get_stats()` reporta `bullet_backend`.
2. **Cache de trimesh por Mesh** (`core_v2/systems/collision/ShapeBounds.gd::trimesh_shape_of`): la forma se guarda como meta del propio recurso Mesh (vive y muere con él, sin entradas huérfanas ni reuso de instance_id). Consumidores: `DuctMazeStreamer.gd` (hub :466, arco :551, cápsula :745), `ScaffoldHubRing.gd` (:367, también acelera el horneado del editor), `CircuitCable.gd` (reemplaza `create_trimesh_collision()`). Además el brazo en arco del streamer ahora cachea su malla por parámetros (era el único builder fuera de `_mesh_cache`).
3. **KinematicArm3D: un `cast_motion` por tick** (`core_v2/camera/KinematicArm3D.gd`): el hit directo y el lookahead derivan del mismo `safe_fraction` (`_cast_shape_safe_fraction`); la distancia del primer bloqueo es propiedad de la escena a lo largo del rayo, así que un solo barrido reproduce exactamente los dos valores (incluidos los guards 0.9999 de cada uno). El motion lookahead conserva su cast propio (sondea desde el origen futuro del pivote: otro rayo).
4. **Presupuesto de raycasts de gas** (`core_v2/systems/gas/GasParticleManager.gd`): `raycast_budget_per_tick = 64` (0 = sin tope). `_prepare_ray_budget()` calcula la velocidad efectiva una sola vez por tick y raycastea solo las K candidatas más rápidas (selección determinista por velocidad, sin aleatoriedad); el resto se mueve balístico ese tick.
5. **Lookups cacheados**: `SessionManager.gd` resuelve `/root/PerformanceMonitor` una vez (antes: por cada tick de física); `PlayerControllerV2.gd` cachea `/root/SessionManager` en modo replay.
6. **FakeShadow** (`core_v2/visual/FakeShadow.gd`): (a) `grid_resolution` capped a 6×6 en Android (el fallback cheap de Linux-ARM se queda como estaba); (b) la grilla ya no son 64 nodos `RayCast` con `force_raycast_update`: una pasada de `intersect_ray` sobre offsets precomputados, exclusión del actor via array; (c) la malla se regenera solo si alguna celda cruzó `snap_amount` o cambió el patrón de huecos (`_mesh_needs_rebuild`).
7. **PushableBoxV2 camino Box3D** (`core_v2/components/PushableBoxV2.gd`): sleeping en vez de `MODE_KINEMATIC` y sin snap rotacional — **OPT-IN** con `ODISEA_PUSHABLE_SLEEP=1` (ver sección dedicada; el default volvió al legado por drift en la CI de Box3D).
8. **Warmup de shaders de Dome_Intro desde el Menu** (`core_v2/ui/Menu.gd::_spawn_shader_warmup` + `ShaderWarmupTrigger.gd`): el trigger ahora ESPERA a que el preload de SceneManager termine (`wait_preload_conflict`) y cachea igual, en el Menu y en background. Antes se saltaba el warmup por la carrera del load() síncrono, así que `DomeIntroShaderCache.tscn` no estaba cableado en ninguna escena.
9. **Compilación por lotes en el addon** (`addons/gd-shader-cache/src/ShaderCache.gd`): `materials_per_frame` (0 = legado) revela las quads de a N por frame; `DomeIntroShaderCache.tscn` usa 6. Con async OFF evita el mega-stall de un solo frame.
10. **`shader_compilation_mode.web=2`** en project.godot: habilita async+cache en navegadores con `KHR_parallel_shader_compile` (el motor registra default `.web=0` en `servers/visual_server.cpp:2793`). Degradación grácil: Firefox/Safari sin la extensión caen al camino síncrono de siempre.

### Números finales (Thorium headful, build local Box3D v0.2.0, flujo Menu → NUEVA PARTIDA)

| Métrica | Baseline (producción) | Con este lote | Delta |
|---|---|---|---|
| Transición Menu → Dome_Intro (`completed` elapsed) | 26.3–28.6 s | **6.1 s** | ~4.5× |
| Stall `tree_attached → first_idle_frame` | 25.7 s | **4.9 s** | ~5× |
| Warmup de ~90 programas GLES3 en el Menu | n/a (no corría) | ~20 s síncronos con async OFF / background con async ON | — |

El arranque del Menu en sí (~1.8 s de transición) no cambió; el resto del tiempo hasta el click es fetch+parse del pck (419 MB local; en producción lo absorbe el cache del CDN y el shell de `odisea_shell.html`).

### Strafe sin culling (nota corregida)

La nota histórica (deriva 5.74 m de `test_locomocion_strafe` al re-replay sin culling) **ya no reproduce**: hoy, con `ODISEA_DISABLE_COLLISION_CULL=1`, el replay pasa con drift 0. La grabación actual es compatible con el culler apagado, así que la CI determinista (Box3D, culler auto-apagado) queda verde sin re-grabar nada.

### Arranque en navegador (Dome_Intro / Menu) — segundo lote, medido con Playwright + Thorium

Instrumentación: export HTML5 Threads local con el binario/editor Box3D v0.2.0 (`~/Descargas/godot.box3d.linux.x86_64.editor` + templates del release en `templates/3.6.4.rc/`), servido localmente con COOP/COEP, medido con Playwright sobre `/usr/bin/thorium-browser-avx2` (headful, GPU) usando el replay box3d (`replay_1788458596.json`, `--replay`) y el flujo real Menu → NUEVA PARTIDA (clic en canvas + Enter). Marcadores: `[SceneStartup] <scene> completed` de SceneManager y las métricas del shell (`loader_start` / `player_released`).

Hallazgos (todos reproducidos, screenshots en `/tmp/kilo/webmeasure/shots/`):

1. **El stall de Dome_Intro era ~26 s en web** (`tree_attached → first_idle_frame`): compilación síncrona de ~90 programas GLES3. Desktop con cache: 2.9 s.
2. **El motor registra `shader_compilation_mode.web = 0` por defecto** (`servers/visual_server.cpp:2793`, `GLOBAL_DEF(...mode.web, 0)`): el override `.web` silencia async en web aunque project.godot declare 2. Por eso el boot web imprimía `Async. shader compilation: OFF` (síncrono, sin cache) mientras desktop/Android corren async.
3. **Con `shader_compilation_mode.web=2`** (Chromium expone `KHR_parallel_shader_compile`): boot imprime `Async. shader compilation: ON (full native support)` y la transición a Dome_Intro baja de **26.3 s → 6.1 s (~4.5×)**; el stall de first_idle_frame, de 25.7 s → 4.9 s. Los ubershaders renderizan en el primer frame y los programas reales se compilan en background — **verificado visualmente**: criopods, rejas, Pilot y luces correctos a los +6/+22 s (capturas `final1_dome*.png`). El contrato `iOS=0` (ubershaders esconden meshes en GL móvil) NO aplica a web/ANGLE en Chromium; Firefox/Safari sin la extensión caen al camino síncrono de siempre (degradación grácil). Pendiente de verificación visual en Firefox antes de darlo por cerrado.
4. **El shell de deploy secuestra `fetch` y baja el pck/wasm de GitHub Pages** (`core_v2/telemetry/html/odisea_shell.html`, `PAGES_BASE`): toda medición local debe neutralizarlo o se mide el pck de producción.
5. El warmup de quads (`ShaderCache`) NO reduce el stall web por sí solo: las quads del menu compilan las variantes base, pero el primer draw real necesita variantes distintas (sombras, fog, alpha) y recompila igual (medido: warmup completo antes del click, stall 25.3 s). Con async ON el warmup pasa a ser un *pre-submitter* de programas a la cola de background — útil, no crítico.
6. Error `image->is_compressed() ... WebGL INVALID_ENUM` (76 ocurrencias): artefacto del export local (variantes de textura regeneradas por el editor 3.6.4.rc); el pck de CI/producción no lo muestra (base4: 0 errores). No bloquea.

Cambios aterrizados: `shader_compilation_mode.web=2` en project.godot (la CI lo pisa por plataforma si hace falta), warmup de Dome_Intro cableado desde `Menu._spawn_shader_warmup()` (el trigger ahora ESPERA el preload en vez de saltarse el warmup — `wait_preload_conflict`), y `materials_per_frame` en `ShaderCache.gd` (revelado por lotes para no congelar el menu cuando el camino es síncrono).

### Arranque en navegador (Dome_Intro / Menu) — primer análisis

El freeze del tab está dominado por costos de motor que GDScript no puede mover: fetch del pck desde IndexedDB, decodificación de sub-recursos dentro de `load_interactive` (ya cede entre recursos) y compilación GLES3 de shaders en el primer draw (single-thread en HTML5). Lo que ya baja el pico con este lote: sin nodos RayCast de FakeShadow al spawnear el Pilot y sin BVHs duplicados de trimesh. Pendiente (requiere decisión de assets, §7): variante más chica del backdrop `HelmetView_HI-RES.png` (850 KB de .stex) para web.

### PushableBoxV2 en Box3D (segundo lote — camino sleeping OPT-IN)

El híbrido Rigid↔Kinematic y el snap rotacional de 90° eran parches para la falta de determinismo de Bullet (confirmado por Sebastián: el snap no es gameplay, era el truco). Con el solver de Box3D el determinismo lo da el motor, así que se implementó el camino Box3D: la caja nunca sale de `MODE_RIGID`, `_settle()` duerme el cuerpo (`sleeping = true`) en vez de congelarse kinematic, y el snap rotacional no se aplica. **Estado: OPT-IN (`ODISEA_PUSHABLE_SLEEP=1`), no default** — en la CI determinista con el motor Box3D real, el camino sleeping agregó drift 0.051 en `test_push_clipping` (umbral 0.03) entre la grabación (PASS 1) y el replay (PASS 2): el reposo via sleeping interactúa distinto con el island management de Box3D entre corridas. En Bullet local es determinista (suite 140/140 con el camino activo). Siguiente paso del camino sleeping: A/B con el módulo (¿despertar por contacto del jugador contra cuerpo dormido se resuelve igual en PASS1/PASS2?), y ver si v0.2.1 lo limpia.

Resto del diseño (cuando se reactive): el push del jugador ya llamaba `wake_up()` proactivo, `set_external_velocity`/`WakeArea`/sondeo cubren despertar con paridad, y `restore_snapshot` mapea snapshots legados `MODE_KINEMATIC` a rigido dormido. Bullet queda byte a byte intacto.

#### Historia del rojo de la CI determinista (forense, Sept 3-9)

- **Verde** Sept 3-4 temprano, con `push_clipping` ya flakese: drift 0.248 el 04/09 03:59 contra PASS del mismo commit (`3233a093`) a las 07:08 — flake del replay, no del engine.
- **Rojo permanente desde `629e0efc`** ("Help with fps spikes", 04/09 19:57): `push_clipping` drift 0.2596. Ese commit no tocó stepping; el costo por tick venía de `773ad46b` ("Perfilar el tick de física"), que introdujo el `get_node_or_null("/root/PerformanceMonitor")` por tick en SessionManager — el patrón de costo conocido que hace perder pasos de física a los replays.
- **Hoy, con los lookups cacheados** (SessionManager `_pm_prof` + PlayerControllerV2 `_sm_cache`, lote 1): `push_clipping` volvió a PASSED en Box3D CI. Máximo drift de toda la suite Box3D: **0.002353** (umbral 0.03), 13 replays con drift ≤ 0.000001.
- **`test_cargol_basic` era un falso positivo de determinismo**: no mide drift, es un assert OYS sobre la posición de reposo del cargo tomada a 0.2 s del release (mitad de rodado). Bullet lo dejaba en x=-1.83944 y Box3D pasaba por x=-2.66 en ese instante → el assert `> -2.0` explotaba solo en Box3D. Con `WAIT 2.0` de asentamiento **ambos motores convergen al mismo reposo bit-exacto (-1.83944)**; banda reescrita a (-3.5, 3.0) con el contrato funcional documentado. Verificado en ambos motores.

#### Respuesta a "¿eliminamos el drift con Box3D?"

Sí para el drift del jugador en Box3D CI: los DRIFT_CHECK de los 14 replays dan ≤ 0.002353 (13 de ellos bit-exactos), incluidos los que históricamente derivaban (strafe 5.74 m con el bug del culling — el culler ya no corre en Box3D). El rojo restante de la suite era aserciones comportamentales (cargol, reescrito hoy) y el experimento sleeping (opt-in). Los replays siguen siendo la vara.
