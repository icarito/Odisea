# Handoff — Bake del RingHub: piso, domo y criopods (2026-09-25)

Objetivo: que el RingHub tenga el look **Dome_Intro** en LIT/DARK — piso, domo y
criopods (incluido el pod de Elías) con el lightmap horneado, sombras entre
andamios y halos de las luminarias — tanto en Desktop como en la Anbernic
(Mali-G31, perfil low-end).

Estado: **bake funcionando** en Desktop y deployado en la Anbernic; tests
GdUnit de las áreas tocadas **en verde**. Queda una (1) feature pendiente
(hazard plate) y validación visual/perf en device.

---

## 1. Cómo se hornea (pipeline)

- Baker headless: `tools/bake_ringhub_lightmap.gd`
  `tools/godot --path . --no-window -s tools/bake_ringhub_lightmap.gd`
  Output: `core_v2/levels/RingHub.lmbake` + un PNG de lightmap por mesh
  (`core_v2/levels/<Nodo>.png`).
  - **`ODISEA_BAKE_FAST=1`** → calidad LOW + hints chicos. **Usar SIEMPRE para
    iterar** (el bake HIGH con sombras y ~200 pods tarda muchísimo). El full es
    el de producción.
  - **`ODISEA_BAKE_LIGHT_MULT=N`** → multiplica la energía de las luces (para
    pruebas "full light").
- Postproceso (tinte + blur): `make bake-lightmap-postprocess` con
  `DOME_LIGHTMAP_DATA_PATH=core_v2/levels/RingHub.lmbake`,
  `DOME_LIGHTMAP_STAMP_DIR=build/lightmap-postprocess/ringhub`,
  `DOME_LIGHTMAP_RAW_DIR=build/lightmap-raw/ringhub`,
  `DOME_LIGHTMAP_FORCE=1`, y knobs `COLORIZE=12 BRIGHTNESS=80 CONTRAST=4`.
- Reimport: `make reimport-lightmap` (regenera los `.stex`; el editor hace
  timeout pero los escribe).
- Build/deploy handheld: `make -B portmaster` + `make portmaster-install`
  (rsync incremental; `PORTMASTER_HOST` default `root@angel.local`).

## 2. Hallazgos clave (por qué antes no se veía)

1. **Godot 3 NO puede hornear `MultiMeshInstance`.** Sólo `GridMap` implementa
   `get_bake_meshes()` (`modules/gridmap/grid_map.cpp`); `multimesh_instance.cpp`
   no. Los anillos de criopods decorativos son MultiMesh → nunca reciben bake.
   Solución: `CriopodRingVisualV2` los reemplaza por **pods instanciados**
   (`CriopodParallax.tscn`, MeshInstance bakeables). Gate: **default ON**, se
   apaga con `ODISEA_CRIOPOD_RING_INSTANCED=0`.
2. **El baker saltea hijos con `owner == null`**
   (`BakedLightmap::_find_meshes_and_lights`: `if (!child->get_owner()) continue;`
   *"maybe a helper"*). Los pods instanciados en runtime no tenían owner → no se
   horneaban. Fix: en `_instance_bakeable_pods` se setea
   `pod.owner = _scene_root()` (la raíz real del nivel; en el bake no hay
   `current_scene`).
3. **Nombres deterministas.** Con el autorrenombre (`@Criopod@N`) el path del
   lightmap no coincidía entre bake y runtime → `_assign_lightmaps` logueaba
   `Node not found`. Fix: `pod.name = "Pod_<Ring>_<NN>"`.
4. **Timing de `_assign_lightmaps`.** Corre en el `NOTIFICATION_READY` del
   BakedLightmap, ANTES de que existan piso/pods generados en `_ready` → no los
   encuentra. Dos fixes:
   - Los pods se crean en **`_enter_tree`** (existen antes de cualquier READY);
     la posición se aplica en `_ready` (en `_enter_tree` `global_transform` aún
     no es válido).
   - Re-asignar diferido desde `RingHubLightState._reassign_lightmaps_after_ready`
     usando el **setter bound** `light_data` (re-set null→data). **NO** usar
     `call("_assign_lightmaps")`: no está bound en el build headless y rompe los
     tests GdUnit.
5. **`lightmap_unwrap` no existe en release** (`array_mesh_lightmap_unwrap_callback`
   es del editor/import) → el piso generado en runtime quedaba sin UV2. Fix: UV2
   **analítica** (proyección planar XZ) en `ScaffoldHubRing._ensure_lightmap_uv2`,
   determinista e idéntica en bake y runtime.
6. **Low-end usa el lightmap NATIVO.** En Mali el nativo ya funciona con el driver
   nuevo del fork. En flat (`unshaded`) el lightmap nativo NO se samplea, así que
   para lightmaps en handheld el perfil es el nativo: `portmaster/Odisea.sh`
   ahora setea `ODISEA_UNSHADED=${ODISEA_UNSHADED:-0}` (flat se fuerza con =3).

## 3. Cambios principales

- `tools/bake_ringhub_lightmap.gd` — bake con todas las luces del nivel, pool off
  (`MobileLightBudget.set_budget_enabled(false)`), excluye dinámicas
  (Pilot flashlight/fill, ButtonLight del pedestal), `shadow_enabled` en las
  luces y `cast_shadow=ON` en andamios/domo/piso/pods (halos), hints de lightmap
  (domo/piso 2048, pods 128), `ODISEA_BAKE_FAST`, `ODISEA_BAKE_LIGHT_MULT`, y
  fuerza `ODISEA_CRIOPOD_RING_INSTANCED`.
- `core_v2/levels/chunks/ringhub/CriopodRingVisualV2.gd` — pods bakeables
  (nombres deterministas, owner, creación en `_enter_tree`, gate default ON).
- `core_v2/props/scaffold/ScaffoldHubRing.gd` — `use_in_baked_light`, UV2
  analítica y hint 2048 en el `CombinedMesh` regenerado (el override de escena se
  perdía).
- `core_v2/levels/RingHubLightState.gd` — re-assign diferido del lightmap;
  export `pool_energy_scale` (no aplica en low/flat).
- `core_v2/levels/RingHub_Level.tscn` — `lightmap_energy_dark=0.5`,
  `lit=6`, `lit_ambient_energy=1.8`, `lit_sun_energy=0.3`, `lamp_on_emission=1.6`,
  `lamp_lights_enabled=false`; Sun vertical; `DarkLevelLighting.fog_enabled=false`;
  `grate_emission_energy=0.0` en los 5 pisos; `use_in_baked_light` + hints en
  DomeMesh/pisos.
- `core_v2/levels/DarkLevelLighting.gd` — export `fog_enabled`.
- `tools/bake_criopod_lightmap_uv2.gd` — genera y **persiste** UV2 en las mallas
  de criopods (pod de Elías, parallax, y los `.mesh` compartidos de anillos).
- `core_v2/autoloads/GLES3VendorGate.gd` — el lightmap manual
  (`IOSLightmapFallback`) pasa a ser **opt-in** (`ODISEA_MANUAL_LIGHTMAP=1`); el
  default es el nativo.
- `portmaster/Odisea.sh` — default `ODISEA_UNSHADED=0` (nativo con lightmaps).
- `FlatFake*.shader` + `IOSLightmapFallback.gd` — soporte de lightmap opcional
  con `lightmap_mix` (default 0 = no-op). **Hoy inerte** (flat no lo activa).
  Revertir o dejar; no afecta el camino nativo.

## 4. Reproducción y tests

- Bake rápido: `ODISEA_BAKE_FAST=1 tools/godot --path . --no-window -s tools/bake_ringhub_lightmap.gd`
  Debe imprimir `bake: usuarios ring=205 total=232`.
- Verificar membresía sin mirar imágenes: probe que lista `get_user_path(i)` del
  `.lmbake` (los anillos deben figurar como
  `../ScaffoldStreamRoot/Criopods_Visual_CriopodsN/Pod_CriopodsN_XX`).
- Tests (deben quedar verdes):
  `./.venv/bin/pytest tests/test_odisea_runner.py -k "ringhub_chunk_streaming or ringhub_light_state"`
  Repro histórico del bug: `SCRIPT ERROR: Invalid call. Nonexistent function
  '_assign_lightmaps (via call)'` (por `call` en headless) y `Node not found
  ".../Pod_CriopodsN_XX"` en `_assign_lightmaps`/`_clear_lightmaps`.

## 5. Pendientes

1. **Hazard plate bajo los criopods** (RingHub no la tiene, Dome_Intro sí).
   Encontrado por material `seam_hazard_stripes` en
   `core_v2/levels/interiors/RingHub_IndustrialRailing.tscn`,
   `RingHub_ScaffoldSource.tscn`, `SteelGratePlatform.gd`,
   `ScaffoldHubRing.gd`; falta identificar el nodo puntual de Dome_Intro bajo los
   pods y replicarlo.
2. **Validar en la Anbernic**: lanzar el juego y confirmar que pods, pod de
   Elías, piso y sombras se ven; medir con `tools/anbernic_probe.sh <tag> 90 4`
   contra el baseline flat (fps ~25 / dc 73). Si el PBR nativo sale caro,
   `ODISEA_UNSHADED=3` (pero sin lightmaps) o `ODISEA_CRIOPOD_RING_INSTANCED=0`.
3. **Commit + push del trabajo abierto** (`[build:all]` para el nightly) — al
   cierre de esta sesión la mayoría de estos archivos están **sin commitear**
   (ver `git status`; hay ~200 lightmaps de pods nuevos, nombres `Pod_*.png`).
4. Los lightmaps viejos de pods con nombre `@Criopod@*.png` quedaron obsoletos;
   borrarlos si no se usan.
5. Decidir si se revierte el soporte de lightmap en `FlatFake*.shader` +
   `IOSLightmapFallback` (inertes).

## 6. Workflow que pidió Sebastián

Después de un bake **rápido**, levantar el juego para que lo mire **antes** de
gastar el bake full. Y para el perfil flat: `ODISEA_UNSHADED=3` (no hay lightmap).
Comando útil: `tools/launch_game.sh --scene res://core_v2/levels/RingHub_Level.tscn`
(agregar `--lowend` para el perfil handheld con `override.cfg` de
`portmaster/lowend.cfg`).
