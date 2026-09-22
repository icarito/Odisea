# FD-314: Streaming de superestructura de scaffold en RingHub (MultiMesh + colisiones por chunk)

**Status:** Implemented (validado en device 2026-09-22; ver follow-ups en §9)
**Priority:** P1
**Effort:** Large
**Created:** 2026-09-21
**Parent:** FD-032 (Seamless Startup/Area Streaming) · FD-021 (Scene Transition System)
**Relacionadas:** `tools/bake_scaffold_walkways.gd` · `tools/bake_dome_intro_hub_floors.gd` · `tools/bake_ring_collider_primitives.gd` · `core_v2/levels/chunks/DeferredSceneChunk.gd` · `docs/features/FD-032_seamless_startup_streaming.md` · `docs/handoff/anbernic-lowend/plan.md`

---

## 1. Resumen y Contexto

`RingHub_Level.tscn` es el **Nivel 1** real del juego: es el `FIRST_GAME_SCENE` de
`core_v2/ui/Menu.gd`, el primer nivel que carga el jugador y el que valida el
arranque del Vertical Slice. Hoy su superestructura de scaffold es mínima: solo
el `RingFloor` (un `ScaffoldHubRing` horneado con `CombinedMesh` + `StaticBody`
de 8 segmentos) dentro del nodo `Hub`.

El resto de la geometría de scaffold — **HubSpokes** (conectores radiales),
**ScaffoldSpiral** (SpiralStairs + SpiralWalkways) y **ScaffoldHubTower** — ya
existe y está resuelta en `Dome_Intro` (ver `Dome_Base.tscn`: grupos
`SpiralStairs`/`HubSpokes`/`SpiralWalkways` con `MeshInstance` por sector
horneado + `StaticBody` con colisiones reparentadas, y la torre con
`CombinedMesh`/`CombinedCollision` por piso). Esa resolución demostró el patrón
ganador:

1. **Visual**: cada grupo se hornea a meshes por sector (`DomeIntro_<Group>_sector_XX.mesh`) y se instancia como pocos `MeshInstance`, o se colapsa a `MultiMesh` (ver `ScaffoldHubRing._collapse_segments()` → `BatchedMeshes`).
2. **Colisión**: nunca se deriva del mesh combinado (el trimesh sobre tubos y rieles produce colliders cóncavos que estrechan el camino). Se reparentan las `CollisionShape` limpias de cada plataforma bajo un solo `StaticBody`, guardado como sub-escena `*_body.tscn`.

Esta FD traslada ese patrón a `RingHub_Level.tscn` y le agrega la pieza que le
falta: **streaming**. La superestructura (spokes, espiral, torre) no se instancia
toda al arrancar; entra por **chunks** según la posición del jugador
(`DeferredSceneChunk`), con las colisiones diferidas y la gráfica en `MultiMesh`.

**Por qué ahora:** el plan low-end (`docs/handoff/anbernic-lowend/plan.md`,
2026-09-20) midió `Dome_Intro` a 2–3 fps en RG351V. RingHub como Nivel 1 es el
nivel más jugado; si su superestructura completa entra toda al arrancar, paga el
mismo costo de draw calls y colisiones que Dome_Intro. El streaming convierte ese
costo de "todo siempre" a "lo que está a la vista".

---

## 2. Objetivos

- **O1. RingHub real como Nivel 1**: `RingHub_Level.tscn` deja de ser un hub
  vacío y recibe la superestructura completa (spokes + espiral + torre),
  reutilizando la autoría y el bake de Dome_Intro sin duplicar contenido.
- **O2. Gráfica barata**: cada grupo de scaffold se ve como `MultiMesh`/meshes
  horneados por sector (decenas de draw items por plataforma → 1–8 por grupo).
- **O3. Colisiones streamed**: los `StaticBody` con sus `CollisionShape` y
  `FootstepSurface` entran como sub-escenas diferidas (`DeferredSceneChunk`),
  no al `_ready()` del nivel.
- **O4. Sin regresión de gameplay**: el determinismo/replay del `Core V2` se
  respeta (los cuerpos del `replay_sync` restauran snapshot antes de habilitar
  física; ver §6).
- **O5. Reutilizar, no inventar**: misma maquinaria de FD-032
  (`SceneManager.load_interactive`, `DeferredSceneChunk.gd`, `StartupTrace`,
  airlocks, `CollisionCullManager`).
- **O6. Criocápsulas baratas**: los criopods decorativos (`CriopodParallax`)
  existen **siempre** como `MultiMesh` (carcasa / vidrio / tarjeta) — visual
  constante y barato — y su **colisión entra por chunk** según el piso/anel de
  la torre al que el jugador accede. Ver §4.5.

**Fuera de scope (backlog):**
- Modificar `Dome_Intro` (queda como está; el tooling se parametriza con
  `ODISEA_BAKE_SOURCE`/`ODISEA_OUT_PREFIX`, que ya existen).
- Streaming de sistemas de gameplay (DDC, IA, puzzles): eso es el patrón de
  chunks de gameplay de FD-032, otra FD. Las criocápsulas **sí** entran aquí
  (§4.5), pero solo su visual + colisión, no su interacción.
- LOD dinámico o culling por cámara de la superestructura: el chunk por radio
  ya cubre el caso low-end de esta FD.

---

## 3. Estado actual verificado

| Ítem | Dónde | Detalle |
|---|---|---|
| `FIRST_GAME_SCENE` | `core_v2/ui/Menu.gd` | `res://core_v2/levels/RingHub_Level.tscn` |
| `RingFloor` | `RingHub_Level.tscn` `Hub/RingFloor` | instancia `ScaffoldHubRing.tscn`, `outer_radius=13.0`, `inner_radius=6.0`, `sides=8`; horneado: `CombinedMesh` + `StaticBody` con `RingFloorSeg_0..7` y `RingRailOuter_*` |
| Bake de anillo | `tools/bake_ring_collider_primitives.gd` | genera los primitivos de colisión del piso del ring |
| Grupos scaffold en Dome | `Dome_Base.tscn` | `SpiralStairs` (Sector_00..07), `HubSpokes` (Sector_00,05,06,07), `SpiralWalkways` (Sector_00..06), `ScaffoldHubTower` (Floor_1..5) |
| Meshes horneados | `core_v2/levels/interiors/` | `DomeIntro_<Group>_sector_XX.mesh` + `DomeIntro_<Group>_body.tscn` (StaticBody + CollisionShapes + FootstepSurface) |
| Bake de espiral/spokes | `tools/bake_scaffold_walkways.gd` | grupos `["SpiralStairs","HubSpokes","SpiralWalkways"]`, 8 sectores, texel 0.2, respeta `ODISEA_BAKE_SOURCE`/`ODISEA_OUT_PREFIX` |
| Bake de torre | `tools/bake_dome_intro_hub_floors.gd` | rehornea `CombinedMesh`/`CombinedCollision` de todos los pisos |
| Colapso a MultiMesh | `ScaffoldHubRing.gd` `_collapse_segments()` | agrupa por categoría+tamaño, genera `BatchedMeshes` (MultiMeshInstance, layers 64, cast_shadow ON); las colisiones quedan en cada segmento |
| Streaming | `core_v2/levels/chunks/DeferredSceneChunk.gd` | exports `chunk_scene`, `wait_for_startup_gate`, `startup_wait_max_frames`, `startup_trace_label`; espera `SessionManager.is_startup_gate_open()` |
| Gestión de colisiones | `core_v2/autoloads/CollisionCullManager.gd` | autoload existente para culling de colisiones |

**Nota de nombres:** el usuario se refiere a los grupos como **HubRings**
(pisos anillo), **HubSpokes** (conectores radiales) y **ScaffoldSpiral** (Stairs
+ Platform/Walkways). En el código actual: `ScaffoldHubRing`, `HubSpokes`,
`SpiralStairs` + `SpiralWalkways`. Esta FD usa los nombres de código y aclara la
correspondencia en §4.

---

## 4. Diseño

### 4.1 Arquitectura por capas (mismo espíritu que FD-032)

```
RingHub_Level.tscn  (shell / capa 0)
├── Pilot + SpawnPointV2 + wakeup (RingHubWakeup.gd)
├── WorldEnvironment + Sun + BakedLightmap
├── Hub/RingFloor  (piso anillo horneado — SIEMPRE cargado: es el piso del spawn)
├── Airlock_* (N/S/E/W)  — transiciones
└── ScaffoldStreamRoot  (nodo contenedor de chunks)
    ├── Chunk_Spoke_N  → DeferredSceneChunk → RingHub_HubSpokes_sector_XX_body.tscn + MultiMeshInstance visual
    ├── Chunk_Spiral_N → DeferredSceneChunk → RingHub_SpiralStairs_sector_XX_body.tscn  + MultiMeshInstance visual
    ├── Chunk_Walk_N   → DeferredSceneChunk → RingHub_SpiralWalkways_sector_XX_body.tscn + MultiMeshInstance visual
    └── Chunk_Tower_N  → DeferredSceneChunk → RingHub_Tower_Floor_N_body.tscn + MultiMeshInstance visual
```

- **Shell** (capa 0): lo que el jugador ve al despertar. Barato por definición:
  piso del ring + piloto + ambiente. La superestructura NO existe hasta que el
  jugador se acerca.
- **Chunks** (capas 1..N): cada uno es una instancia de `DeferredSceneChunk`
  con `chunk_scene = RingHub_<Grupo>_sector_XX_body.tscn` (solo colisiones +
  footstep) y un `MultiMeshInstance` como hermano visual.
- **Visual vs físico separados**: el `MultiMeshInstance` es estático y barato;
  puede estar pre-cargado (un recurso `MultiMesh` compartido) mientras las
  colisiones entran diferidas. En la práctica, el chunk adjunta AMBOS: el mesh
  primero (un frame), el `StaticBody` al siguiente `physics_frame` — así nunca
  hay un frame con colisión sin visual ni visual sin colisión.

### 4.2 Regla de partición

- **Un chunk = un sector de un grupo** (anillo de 8 sectores → 8 chunks de
  spokes, ~8 de espiral, ~8 de walkways, 5 de torre; total ~25–30 chunks).
- **Trigger**: `Area`/`Position3D` ancla con radio (típicamente el radio del
  grupo + margen de 8–10 m). Al entrar → `load_interactive`; al salir → opcional
  liberar (`queue_free`) para devolver memoria en low-end.
- **Sin `get_parent()` cruzado**: los chunks se comunican por `EventBus` /
  `SceneManager`, nunca por jerarquía. Los chunks son hermanos bajo
  `ScaffoldStreamRoot`.
- **Colisiones horneadas por chunk**: mismo patrón del ring floor — nunca una
  segunda `.tscn` solo de colisión derivada del mesh combinado.

### 4.3 Reutilización del bake existente

- `bake_scaffold_walkways.gd` ya soporta fuente y prefijo por env var. Para
  RingHub se corre con `ODISEA_BAKE_SOURCE=res://core_v2/levels/RingHub_Level.tscn`
  y `ODISEA_OUT_PREFIX=RingHub`, o se crea un `RingHub_ScaffoldSource.tscn`
  hermano de `DomeIntro_ScaffoldSource.tscn` (misma autoría, mismo
  `RadialScatter`/`SteelGratePlatform`), sin tocar los archivos de Dome_Intro.
- Los pisos de la torre reutilizan `bake_dome_intro_hub_floors.gd` con el mismo
  mecanismo de prefijo.
- `ScaffoldHubRing._collapse_segments()` ya produce `BatchedMeshes`; el FD solo
  exige que esa salida se pueda **guardar como recurso** (`MultiMesh` a `.tres`)
  para compartirla entre shell y chunks.

### 4.4 Grupos y correspondencia

| Grupo (naming del usuario) | Nodo/s código | Contenido horneado |
|---|---|---|
| HubRings | `ScaffoldHubRing` (RingFloor) | `CombinedMesh` + `RingFloorSeg_0..7` — ya horneado, se mantiene en shell |
| HubSpokes | `HubSpokes` | `RingHub_HubSpokes_sector_XX.mesh` + `_body.tscn` |
| ScaffoldSpiral — Stairs | `SpiralStairs` | `RingHub_SpiralStairs_sector_XX.mesh` + `_body.tscn` |
| ScaffoldSpiral — Platform | `SpiralWalkways` | `RingHub_SpiralWalkways_sector_XX.mesh` + `_body.tscn` |
| Torre (opcional en esta FD) | `ScaffoldHubTower` | `RingHub_Tower_Floor_N.mesh` + `_body.tscn` |

### 4.5 Criocápsulas (mismo patrón, dos velocidades distintas)

El usuario lo planteó bien y hay **precedente exacto** en el repo. Hoy
`RingHub_Level.tscn` tiene `Hub/Criopods` con **29 instancias de
`CriopodParallax.tscn`**, cada una con su propio `StaticBody` + `CollisionShape`
(`CriopodParallax.tscn` trae colisión adentro). Eso son ~29 cuerpos estáticos
vivos desde el arranque, y no hacen falta: el jugador no los toca hasta que se
acerca.

**Precedente a reutilizar (no hay que inventar nada):**

- `tools/bake_dome_intro_criopods.gd` ya hornea criopods a **3 mallas por anillo**
  (`_shell`, `_glass`, `_cards`) + **un `StaticBody` por anillo** con las cajas de
  colisión. Documenta exactamente por qué **3 nodos y no 1 con 3 superficies**: la
  carcasa entra al shader de dither y recibe el `next_pass` de hielo, el vidrio es
  transparente (rechaza el dither), y la tarjeta del piloto está en el grupo
  `no_occlusion` (PropDitherManager la saltea). Si van en un solo nodo, las tres
  comparten el destino de la primera.
- `docs/features/FD-032` §Phase 4 ya define el camino objetivo: **escena fuente
  editada → recurso de layout horneado → escena runtime que arma `MultiMesh` de
  shell/glass/cards + colisiones diferidas generadas del mismo layout**. También
  exige preservar flags de `GeometryInstance` (cast_shadow, layers,
  use_in_baked_light) en los `MultiMesh`, y que el `PersonCard` LOD **no** proyecte
  ni reciba sombras.

**Diseño propuesto (dos velocidades):**

1. **Visual — siempre presente, barato.** Los criopods existen como `MultiMesh`
   desde el shell: 3 `MultiMeshInstance` por anillo (shell/glass/cards), material
   compartido. Un anillo de ~37 pods pasa de 37 draw items a 3. Esto no espera al
   jugador: el ring de criopods es el telón de fondo del Nivel 1 y debe verse
   siempre (incluso en la cinemática de despertar).
2. **Colisión — por chunk, diferida.** La colisión del anillo entra como
   `DeferredSceneChunk` cuando el jugador entra en el radio/nivel correspondiente
   (piso de `ScaffoldHubTower` o anillo del hub). En low-end, si el jugador está
   en otro piso, esas cajas no están en el mundo físico.

**Matiz de "aparecen o se mueven" (nota para el implementador):** mover un
`StaticBody` de colisión en runtime (en vez de instanciarlo/liberarlo) es válido
si el chunk se limita a **reposicionar** el `StaticBody` horneado de un anillo
hacia el piso activo delante de la cámara. Es más barato que instanciar, pero
pierde la separación por anillo y complica el determinismo si un cuerpo del
`replay_sync` queda dentro. **Recomendación: instanciar/liberar por chunk
(§4.2)**, no reparentar/mover, salvo que la medición low-end lo justifique luego.

**Criopod funcional (`Criopod_Vert`, despertar):** queda **en el shell**, nunca en
un chunk. Es el punto de spawn, tiene `CinematicSequence` y `WakeupFloor` con
colisión, y su terminal es interactuable — no puede depender de un chunk streamed.


1. **Tooling**: parametrizar/verificar el bake para RingHub (`ODISEA_BAKE_SOURCE`
   + `ODISEA_OUT_PREFIX`) y generar `RingHub_*_sector_XX.mesh` +
   `RingHub_*_body.tscn` para spokes, espiral y walkways (torre si entra).
2. **Recurso MultiMesh compartido**: guardar la salida de `_collapse_segments()`
   como `.tres` por grupo (un MultiMesh por sector o uno por grupo con
   instancias).
3. **Chunk scenes**: `core_v2/levels/chunks/ringhub/` con `DeferredSceneChunk`
   por sector (colisiones + footstep + MultiMesh visual) y anclas con radio.
4. **Shell actualizado**: `RingHub_Level.tscn` con `ScaffoldStreamRoot`, anclas
   posicionadas contra los hitos de la autoría fuente (mismas transformadas que
   en `Dome_Intro`/`DomeIntro_ScaffoldSource.tscn`), `AirlockManager` intacto.
5. **Tests**:
   - `test_ringhub_wakeup.gd` sigue verde (el shell no cambia el arranque).
   - Nuevo test de chunk: entrar al radio → colisión presente en ≤N frames;
   - salir → liberación opcional; determinismo: `replay_sync` restaura snapshot
   antes de habilitar física (§6).
   - Test de paridad de posiciones: cada chunk en RingHub coincide (tolerancia
   < 1 cm) con su contraparte en `DomeIntro_ScaffoldSource.tscn`.
6. **Criocápsulas** (§4.5): bake de los anillos de criopods de RingHub a
   `MultiMesh` (shell/glass/cards) + `StaticBody` de colisión por anillo; los 3
   `MultiMeshInstance` viven en el shell; la colisión entra por chunk.
   - Test: conteo de pods visuales == conteo del layout horneado; flags de
     `GeometryInstance` preservados (cast_shadow, layers, use_in_baked_light);
     `PersonCard` sin sombras.

---

## 6. Contrato de determinismo / replay

- Los cuerpos de `replay_sync` (`PushableBoxV2`, `CryoPod`) **nunca** cuelgan de
  un chunk streamed si el snapshot puede referenciarlos antes de que el chunk
  exista. El chunk adjunta colisión en el `physics_frame` posterior a la
  restauración de snapshot, y los cuerpos interactuables del ring (zona spawn)
  quedan en el shell, no en chunks.
- `DeferredSceneChunk` ya respeta `SessionManager.is_startup_gate_open()`:
  ningún chunk se adjunta antes del gate de arranque (mismo contrato que FD-032).
- Cualquier estado serializado que mencione un nodo de chunk debe hacer
  `get_node_or_null` (el chunk puede no estar cargado en el momento de
  restaurar).

---

## 7. Métricas de éxito (low-end RG351V / GLES2)

- **Draw calls**: superestructura completa visible < 12 draw calls por grupo
  (hoy: decenas por plataforma).
- **Colisiones**: colisiones vivas en la escena ≈ solo sectores dentro del
  radio del jugador (objetivo: < 40 shapes activas en el peor punto de la
  espiral), incluyendo las cajas de criopods del anillo activo.
- **Criopods**: ~29 `StaticBody` vivos hoy en `Hub/Criopods` → 0 en el shell;
  visual de cada anillo en **3 draw calls** (shell/glass/cards) en vez de ~29.
- **Arranque**: `StartupTrace` del primer frame jugable sin degradación respecto
  al hub actual (la superestructura no paga en `_ready()`).
- **FPS**: sin caída sostenida bajo el piso del plan low-end (2–3 fps en
  Dome_Intro → objetivo > 20 fps en RingHub con la superestructura completa en
  vista lejana).

---

## 8. Plan de ejecución (fases)

| Fase | Trabajo | Resultado |
|---|---|---|
| A | Bake RingHub (spokes, espiral, walkways, torre) con prefijo propio | `RingHub_*_sector_XX.mesh` + `_body.tscn` |
| A2 | Bake de criopods de RingHub a MultiMesh (shell/glass/cards) + colisión por anillo | anillos visuales baratos + `RingHub_Criopods<N>_body.tscn` |
| B | Guardar MultiMesh por grupo (`.tres`) desde `_collapse_segments()` | recurso visual compartido |
| C | Chunks `DeferredSceneChunk` por sector + anclas con radio en el shell | streaming funcional en editor y build |
| D | Tests de chunk, determinismo y paridad de posiciones | suite verde |
| E | Medición low-end (fase de validación, misma metodología que el plan anbernic) | números §7 |

Fases A–C son delegables a Jules (rama `feature/FD-314-ringhub-scaffold-streaming`),
D–E con revisión por chunks; merge solo con OK explícito de Sebastián.

**Nota de proceso (2026-09-21):** este FD (spec-only) se entrega directo a `main` con
`[build:none]` en el mensaje del commit — un FD no dispara build. Regla: antes de
pushear, verificar que no haya un build en progreso en `main` (Odisea o engine);
si lo hay, esperar a que termine para no interrumpirlo.

---

## 9. Implementación y hallazgos (2026-09-22)

FD implementado en `RingHub_Level.tscn`: superestructura de scaffold (spokes,
espiral, walkways) con visual horneado en el shell y **colisiones streamed** por
chunk (`StreamedSceneChunkV2`, radio 15-16 m + margen de liberación 6 m), más 5
anillos de criopods decorativos con colisión por anillo y 4 pisos superiores del
hub.

Validación en Anbernic RG351V y arreglos posteriores, con detalle y evidencia en
**`docs/engineering/RingHub_Criopods_Device_Notes.md`**:

- **Anillo de despertar**: su `MultiMeshInstance` no se dibujaba en el GLES3
  mobile del device (datos, AABB, materiales y culling verificados correctos; no
  reproduce en local ni con el perfil LOW forzado). Se hornea con geometría
  mergeada (`RingHub_Criopods1_visual.tscn` +
  `tools/bake_ringhub_criopods1_merged.gd`), omitiendo el slot de despertar. Los
  anillos superiores siguen en MultiMesh.
- **Decorativos 20 cm bajo el deck**: `platform_height = 0.2`; +0.2 en los 4
  anillos superiores y `ODISEA_BAKE_RING_Y_OFFSET` en el baker.
- **`rebuild_baked_items = true` es load-bearing**: regenera mesh y trimesh en
  runtime y descarta las primitivas horneadas. Cambiarlo a `false` rompe el
  replay de referencia (drift 29 m) → cualquier cambio de colisión exige
  re-grabar replays.
- **Rendimiento**: Box3D step ≈ 0.25 ms (no es el cuello); el techo es el frame
  (`ms_process` ≈ 29 ms + GDScript ≈ 12 ms/tick). Los 5 anillos del hub todavía
  se regeneran en runtime (~16 ms/anillo) y siguen pendientes de bake, lo que
  requiere re-grabar el replay de referencia.
- **Tests**: `test_ringhub_wakeup.gd` y `test_ringhub_chunk_streaming.gd` siguen
  verdes sin cambios (el merge conserva `slot_to_instance` y el estado
  autoritativo del slot bloqueado); `tools/verify_ringhub_stream.gd` actualizado
  al diseño nuevo.
