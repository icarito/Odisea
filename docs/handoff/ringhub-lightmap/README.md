# Handoff — Lightmap del domo del RingHub (2026-09-25)

Estado: **diagnóstico cerrado**, fix de normales hecho en un worktree aislado,
**falta integrarlo y re-hornear el lightmap**. Dejado acá para que Sebastián
retome el lightmap mientras Kilo sigue con la red/offload del control remoto.

---

## 1. Síntoma

En el RingHub, el lightmap horneado se ve poco en la **cáscara del domo**: el
piso, las pasarelas y los criopods sí se tiñen, el techo/domo queda casi negro.
Además aparecía en el log:

```
E lightmap_capture_set_octree: Condition "p_octree.size() == 0 || ..." is true.
  <Stack Trace> RingHubLightState.gd:302 @ _resolve_nodes()
```

## 2. Diagnóstico (verificado, con números)

1. **El error de octree es benigno y esperado.** `tools/strip_lightmap_capture.gd`
   vacía el `octree` a propósito (ocupa el 99% del `.lmbake` y el lightmap
   estático de Godot 3 no lo usa: usa `user_data` + las texturas PNG). El error
   se dispara igual al `duplicate()` de `RingHubLightState.gd:302` porque
   re-setea el octree vacío. No rompe el bake.
2. **El `.lmbake` está sano.** `core_v2/levels/RingHub.lmbake`: 23 usuarios de
   lightmap, **todos** sus `NodePath` resuelven (`missing_paths=0`), todos con
   `instance=-1` / `slice=-1` / `rect=(0,0,1,1)`.
3. **El bake del domo tiene contenido donde caen sus UV2.** `DomeMesh.png`
   muestreado en los UV2 de la malla del domo da media ~0.42 (brillante), no
   negro. No es UV2 ni el bake.
4. **`verify_ringhub_lightmap_ready.gd` → PASS**: 23 mallas horneables con UV2
   completo; rig `RingHubBakeLights` = 22 luces, apagadas en runtime.
5. **El domo SÍ recibe el bake.** Con la cámara encuadrando la cáscara, subir
   `BakedLightmap.light_data.energy` de 0 a 8 cambia el techo (diff ~6.6 en la
   zona del domo). El A/B anterior daba ~0.4 porque la cámara no encuadraba el
   domo, no porque no llegue.
6. **Por qué se ve poco: el albedo.** En Godot 3 el lightmap entra como
   `ambient_light = lightmap * energy` y luego se multiplica por el albedo del
   material. El domo usa `material_override = RingHub_DomeShell.tres` con albedo
   de hormigón oscuro. Medido en vivo: quitando/aclarando ese albedo el domo se
   ilumina fuerte (mean 22 → 117). El aporte del bake llega; el albedo oscuro lo
   aplasta.
7. **Defecto real aparte: las normales del domo apuntan hacia afuera.**
   `DomeInteriorLowPoly_baked.mesh`: 496 verts, 1 surface, promedio de normales
   `(0, +0.6218, 0.0001)` → outward. Para una cáscara que se ve desde adentro
   deben apuntar hacia adentro. El shader las invierte en runtime para caras
   traseras (por eso la luz dinámica no se ve rota), pero el **baker del lightmap
   usa la normal almacenada tal cual**.

## 3. Fix de normales (hecho, aislado)

Worktree: `/tmp/kilo/dome-normals`, rama `fix/dome-interior-normals`
(base `cb3b7429`, **sin commits**, no toca `main`).

Archivos:
- `tools/bake_dome_interior_lowpoly.gd` — invierte el orden de los índices
  (winding) y niega la normal al reconstruir la surface.
- `core_v2/levels/interiors/DomeInteriorLowPoly_baked.mesh` — regenerado.
- `core_v2/levels/interiors/DomeInteriorLowPoly_baked.shape` — regenerado.

Verificado:
```
ANTES  avg_normal=(0, +0.621843, +0.000077)  dot_radial=+0.9852  tris=240
DESPUÉS avg_normal=(0, -0.621837, -0.000007) dot_radial=-0.9852  tris=240
verify_ringhub_lightmap_ready.gd → PASS
test_gles3_vendor_gate.gd → 22/22 PASSED
```

Notas:
- No hizo falta Blender: el fix vive en el baker. **`scene_dome_lp.py` (el
  generador que citaba el header del baker) NO existe en el repo** — el GLB
  trackeado `assets/models/dome_interior_lowpoly/DomeInteriorLowPoly.glb` es la
  fuente de verdad. El skill de Blender (`docs/skills/blender-bpy.md`) está
  trackeado y registrado por si hace falta tocar el GLB.
- Se mantuvo `CULL_DISABLED` en el material.

Integración: cuando quieras, `git merge fix/dome-interior-normals` (o cherry-pick
el diff) en `main`. Como el `lightmap_unwrap` se rehace, los UV2 por vértice
cambian.

## 4. Pendiente obligatorio tras el fix: re-hornear el lightmap

El `RingHub.lmbake` actual ya no coincide con los UV2 nuevos. Hay que re-hornear
(el editor es el camino preferido; el headless necesita el patch
`lightmap_bake_import` del fork v0.5.0-nightly+).

**Editor (recomendado por Sebastián):**
1. Abrir el editor del fork con `RingHub_Level.tscn` activa:
   `tools/godot --path . -e res://core_v2/levels/RingHub_Level.tscn`
2. Abrir `tools/editor_bake_ringhub_lightmap.gd` y **File > Run** (Ctrl+Shift+X).
3. Godot 3 solo hornea BakedLightmap dentro del proceso del editor.

**Headless (si el fork lo soporta):**
```sh
tools/godot --path . --no-window -s tools/bake_ringhub_lightmap.gd
make bake-lightmap-postprocess \
  DOME_LIGHTMAP_DATA_PATH=core_v2/levels/RingHub.lmbake \
  DOME_LIGHTMAP_STAMP_DIR=build/lightmap-postprocess/ringhub \
  DOME_LIGHTMAP_RAW_DIR=build/lightmap-raw/ringhub
tools/godot --path . --no-window -s tools/verify_ringhub_lightmap_ready.gd   # PASS
```

**Ojo:** el postproceso ImageMagick reusa carpetas por modo
(`build/lightmap-postprocess/ringhub`, `build/lightmap-raw/ringhub`).

## 5. Knobs de visibilidad (además del re-bake)

- `core_v2/levels/RingHub_Level.tscn` nodo `LightState`: **ya cambié**
  `lightmap_energy_dark = 3.0` y agregué `lightmap_energy_lit = 3.0`
  (default era dark=1.0, lit=1.0). Rango del export: 0..16. **Está sin commitear.**
- `RingHubLightState.gd`: `_apply_lightmap(level)` hace
  `energy = lerp(lightmap_energy_dark, lightmap_energy_lit, level)`.
- Si tras el re-bake el domo sigue apagado, el siguiente lever es **aclarar el
  albedo** de `core_v2/levels/interiors/RingHub_DomeShell.tres` (albedo_color /
  textura), no la energía.

## 6. Cómo verificar visualmente (sin editor)

Con ANNA local (peer :4999; requiere `telemetry_enabled=true` en
`userdata/Odisea/settings.cfg`, hice backup en `settings.cfg.kilo-bak`):

```
GET  /eval?expr=get_tree().current_scene.get_node("BakedLightmap").light_data.energy
GET  /eval?expr=...light_data.set_energy(0.0)     # y 8.0, comparar
POST /command {"action":"screenshot"}             # el PNG queda en /tmp/odisea_peer/
```
Encadenar la cámara al domo: `get_node("/root/RingHub_Level/Pilot").set("pitch", 0.9)`
y teleportar cerca de la pared (r≈31) para que la cáscara llene el cuadro.

## 7. Estado de la rama/árbol

- Branch actual: `main` (sucio). Además del bake de Sebastián (`.import/*.stex`,
  `RingHub*.png`, `RingHub_Level.tscn`), Kilo aplicó **sin commitear**: el offload
  del PR #364 (red) + fallback de puertos. Nada de eso es del lightmap.
- El fix de normales NO está en `main` ni en el PCK instalado en el Anbernic.
