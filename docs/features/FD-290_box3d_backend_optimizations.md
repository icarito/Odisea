# FD-290: Optimizaciones del backend Box3D y fruta al alcance de la mano para Odisea
**Status:** Open **Priority:** High **Effort:** Medium **Created:** 2026-09-09 **Reusa:** godot-box3d-3 v0.2.0 (módulo custom), CollisionCullManager, FakeShadow, KinematicArm3D, GasParticleManager

> **Notas de Odiseo:**
> 1. Este FD documenta el lado *Odisea* del estudio hecho en `icarito/godot-box3d-3` (el módulo ya salió optimizado en **v0.2.0**). Cada punto cita archivo y línea del estado del código de hoy; los milisegundos citados vienen de `core_v2/autoloads/CollisionCullManager.gd` (Redmi Note 9 Pro, GLES2), el perfil más restrictivo del proyecto.
> 2. **No cambia gameplay ni determinismo:** todo lo propuesto es de rendimiento y de higiene de carga. Los replays `.oys` existentes siguen siendo la vara.
> 3. Numeración: FD-290 estaba libre en `FEATURE_INDEX.md` al momento de crearlo.

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
