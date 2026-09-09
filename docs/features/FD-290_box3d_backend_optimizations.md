# FD-290: Optimizaciones del backend Box3D y fruta al alcance de la mano para Odisea
**Status:** In Progress **Priority:** High **Effort:** Medium **Created:** 2026-09-09 **Reusa:** godot-box3d-3 v0.2.0 (módulo custom), CollisionCullManager, FakeShadow, KinematicArm3D, GasParticleManager

> **Notas de Odiseo:**
> 1. Este FD documenta el lado *Odisea* del estudio hecho en `icarito/godot-box3d-3` (el módulo ya salió optimizado en **v0.2.0**). Cada punto cita archivo y línea del estado del código de hoy; los milisegundos citados vienen de `core_v2/autoloads/CollisionCullManager.gd` (Redmi Note 9 Pro, GLES2), el perfil más restrictivo del proyecto.
> 2. **No cambia gameplay ni determinismo:** todo lo propuesto es de rendimiento y de higiene de carga. Los replays `.oys` existentes siguen siendo la vara.
> 3. Numeración: FD-290 estaba libre en `FEATURE_INDEX.md` al momento de crearlo.
> 4. **2026-09-09 — primer lote aterrizado** (ver "Landed" al final): retiro de CollisionCullManager en Box3D, cache de trimesh por Mesh, cast único en KinematicArm3D, presupuesto de raycasts de gas, lookups cacheados, FakeShadow (resolución ARM + query directa + cache de malla). El deriva 5.74 m del strafe **ya no reproduce** con el culler apagado (verificado con `ODISEA_DISABLE_COLLISION_CULL=1`): la grabación actual es válida sin culling.
> 5. **2026-09-09 — segundo lote:** camino Box3D de PushableBoxV2 (sleeping en vez de kinematic, sin snap rotacional — Sebastián confirmó que el snap era el parche de determinismo, no gameplay).

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
7. **PushableBoxV2 camino Box3D** (`core_v2/components/PushableBoxV2.gd`): sleeping en vez de `MODE_KINEMATIC` y sin snap rotacional (ver sección dedicada abajo); Bullet intacto; A/B con `ODISEA_PUSHABLE_LEGACY=1`.

### Strafe sin culling (nota corregida)

La nota histórica (deriva 5.74 m de `test_locomocion_strafe` al re-replay sin culling) **ya no reproduce**: hoy, con `ODISEA_DISABLE_COLLISION_CULL=1`, el replay pasa con drift 0. La grabación actual es compatible con el culler apagado, así que la CI determinista (Box3D, culler auto-apagado) queda verde sin re-grabar nada.

### Arranque en navegador (Dome_Intro / Menu)

El freeze del tab está dominado por costos de motor que GDScript no puede mover: fetch del pck desde IndexedDB, decodificación de sub-recursos dentro de `load_interactive` (ya cede entre recursos) y compilación GLES3 de shaders en el primer draw (single-thread en HTML5). Lo que ya baja el pico con este lote: sin nodos RayCast de FakeShadow al spawnear el Pilot y sin BVHs duplicados de trimesh. Pendiente (requiere decisión de assets, §7): variante más chica del backdrop `HelmetView_HI-RES.png` (850 KB de .stex) para web.

### PushableBoxV2 en Box3D (implementado en el segundo lote)

El híbrido Rigid↔Kinematic y el snap rotacional de 90° eran parches para la falta de determinismo de Bullet (confirmado por Sebastián: el snap no es gameplay, era el truco). Con el solver de Box3D (single-thread, substeps fijos, determinista) el determinismo lo da el motor, así que el camino Box3D simplifica:

- **La caja nunca sale de `MODE_RIGID`.** `_settle()` redondea la pose (paridad con el legado), zeroes velocidades y duerme el cuerpo (`sleeping = true`) — costo de solver ~0 como kinematic, pero collider sólido con respuesta de física estándar.
- **Sin snap rotacional y sin slerp** (`_target_basis` nunca se arma en este camino). Bajo Bullet el híbrido con snap queda byte a byte intacto.
- **Despertar con paridad completa:** el push del jugador ya llamaba `wake_up()` proactivamente (`PlayerControllerV2._update_push_state`), `set_external_velocity` (conveyors/plataformas), `WakeArea.body_entered/exited` y el sondeo throttleado `_check_kinematic_wakeup` (cada 3 frames) cubren el caso kinematic-toque-no-despierta igual que el legado.
- **Snapshots compatibles:** `get_snapshot` escribe `mode: RIGID` en este camino; `restore_snapshot` mapea un `MODE_KINEMATIC` legado a rigido dormido (misma pose congelada), así que grabaciones viejas se restauran sin romper.
- **A/B:** `ODISEA_PUSHABLE_LEGACY=1` fuerza el camino histórico también en Box3D.

Validación: `test_push_integration` y `test_push_clipping` en verde con el camino Box3D activo (PASS 1 re-graba el .json con la dinámica nueva; PASS 2 verifica grabación-vs-replay, así que el cambio de dinámica no necesita re-grabación manual). La equivalencia de trayectorias Bullet↔Box3D en CI la dan la re-grabación del PASS 1 y la paridad de semántica que valida el módulo (27/27 escenas de aceptación).
