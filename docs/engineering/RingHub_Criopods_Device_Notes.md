# RingHub criopods: render en device y contrato de streaming (FD-314)

Notas de la validación de FD-314 en el Anbernic RG351V (GLES3 mobile, 981 MB,
tier LOW) y de los arreglos posteriores. Complementa
`docs/features/FD-314_ringhub_scaffold_streaming.md`.

---

## 1. MultiMeshInstance que no se dibuja en el device

**Síntoma.** El anillo de criopods del piso de despertar
(`ScaffoldStreamRoot/Criopods_Visual`, `RingHub_Criopods_visual.tscn`, y=4.5) no
dibujaba ningún pod decorativo en el device. Los 4 anillos superiores
(`Criopods_Visual_Criopods{3..6}`), con el mismo mesh, el mismo script
(`CriopodRingVisualV2`) y los mismos recursos de material, sí se veían.

**Qué quedó descartado** (con el dump real del device, ver §5): cantidad y
transforms de instancias (29 a radio 12.00), AABB, `visible`,
`is_visible_in_tree`, `layers=64`, `cull_mask=1048575` de la cámara, formatos
`transform/color/custom_data` (1/0/0), `material_override` (los mismos
`ShaderMaterial` en el anillo de despertar y en Criopods3) y alfa de los
materiales. En local **renderiza bien** incluso forzando el perfil del device
(`ODISEA_FORCE_LOW_TIER=1 ODISEA_UNSHADED=3`) → es específico del driver.

**Qué se probó sin éxito:** `extra_cull_margin = 3.0`, snapshot/restore del
buffer de transforms alrededor de `duplicate()`, y ocultar la instancia
bloqueada colapsándola en su origen en vez de teletransportarla a `-10000`.
(El teletransporte igual era un defecto real: inflaba el AABB del MultiMesh a
~10000 unidades verticales; ahora la instancia se colapsa en su propio origen.)

**Arreglo.** El anillo de despertar se hornea con **geometría mergeada** en 3
`MeshInstance` (`RingHub_Criopods1_visual.tscn`, generado por
`tools/bake_ringhub_criopods1_merged.gd`): shell 4704 verts, glass 560, cards
1512. Es el mismo camino que usan los visuales de scaffold del nivel, que
siempre renderizaron en el device. El merge **omite la instancia del slot de
despertar** (slot 37 → instancia 26).

Contrato que mantiene:
- conserva `slot_to_instance` de la fuente, así `RingHubWakeup.block_slot(slot)`
  sigue registrando el índice bloqueado (y `hidden_instance_count()` sigue siendo
  1) aunque no haya capas MultiMesh que mover;
- graba `blocked_slot = 37` (var `export`) en la escena, así
  `CriopodRingCollisionV2` libera la caja de ese pod sin depender del orden de
  `_ready()`;
- la geometría ya no incluye ese pod: no queda un decorativo debajo del
  funcional.

**Costo:** si cambia el slot de despertar (`RingHubWakeup.forced_slot`), hay que
rehornear el anillo mergeado. Los anillos superiores siguen en MultiMesh y no
dependen de esto.

---

## 2. Decorativos 20 cm bajo el deck

La superficie caminable de un `ScaffoldHubRing` está a `platform_height = 0.2`
(local al anillo). Los 4 anillos superiores horneaban sus items a `y = 0`, o sea
20 cm dentro del piso.

**Arreglo:** +0.2 m en el anillo (visual y colisión juntos) y nuevo
`ODISEA_BAKE_RING_Y_OFFSET` en `tools/bake_ringhub_criopods.gd` para que
rehornear no deshaga el offset. El anillo de despertar ya traía el offset en su
fuente.

---

## 3. Invariantes y trampas

- **`ScaffoldHubRing.rebuild_baked_items = true`** regenera el anillo en runtime
  (mesh + trimesh) y **descarta las primitivas horneadas** del `.tscn`. No
  ponerlo en `false` para "usar lo horneado": las primitivas no son
  geométricamente equivalentes al trimesh del generador, y el cambio rompe el
  replay de referencia (drift posicional de 29 m en `replay_1790037823`). Toda
  modificación de colisión exige re-grabar los replays.
- **Ocultar una instancia de MultiMesh teletransportándola lejos infla el AABB**
  del MultiMesh (y el culling trabaja con ese AABB). Colapsarla en su origen.
- **`MultiMesh.transform_array`** es un `PoolVector3Array` de
  `instance_count * 4` vectores (3 filas de basis + origen), no de floats.
  El AABB que imprime Godot es `position - size`.
- **`File.READ_WRITE` no crea el archivo en Godot 3**: para el primer volcado hay
  que caer a `File.WRITE`.
- **En el Anbernic el engine debug `frt` es inestable** (se cuelga/mata con
  1 GB). El diagnóstico se hace con el runtime release + dump a archivo por env;
  `eval` sólo existe en builds debug/editor.

---

## 4. Rendimiento medido (release, `replay_1790037823`)

- **Box3D no es el cuello:** `PhysicsServer.get_box3d_profile()` da un step de
  ~0.25 ms.
- **El render tampoco en las poses probadas:** ocultar anillos, pisos y scaffold
  lejanos no movió el fps (19→20) ni los vértices (335k→331k): el frustum
  culling ya los saca.
- **El techo es el frame:** `ms_process` ≈ 28-29 ms + tick de GDScript ≈ 12 ms
  (los 5 anillos del hub todavía se regeneran en runtime, ~16 ms/anillo acá).
- **Ojo con medir sobre replay:** durante un replay la física corre al rate del
  proyecto (60 Hz), no al del tier (LOW = 30 Hz). Los números de replay no son
  los de gameplay.
- **Memoria al límite:** RingHub deja ~70 MB libres en 981 MB.

---

## 5. Herramientas

- `tools/verify_ringhub_stream.gd` — chequeo estático del shell: estructura,
  anillo de despertar mergeado (0 MultiMesh / 3 MeshInstance), bodies de
  colisión, y que la fuente del merge mapee slot 37 → instancia 26. Correr
  headless: `tools/godot --no-window -s tools/verify_ringhub_stream.gd`.
- `tools/bake_ringhub_criopods1_merged.gd` — hornea el visual mergeado del anillo
  de despertar desde el MultiMesh fuente.
- `ODISEA_CRIO_DIAG=1` — el visual vuelca el estado de cada capa MultiMesh a
  `user://crio_diag.txt` (`ready` y `t+1s`). Inerte sin la env.
- Loop en device: `make portmaster-install`, reiniciar (autostart), y replay vía
  `dev.sh` (`GODOT_OPTS="$GODOT_OPTS -- --replay user://replay_....json"`).
  El runtime no-debug es `odisea.frt.aarch64` en el paquete; no hace falta el
  engine debug para medir fps ni para ver el nivel.
