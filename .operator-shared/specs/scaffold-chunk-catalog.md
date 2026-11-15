# Catálogo de chunks de andamio (Transit-Run)

Contrato del catálogo maestro de 10 chunks y de su ensamblado por semilla
(`core_v2/systems/scaffold/ScaffoldChunkRegistry.gd`). Umbrales de alcance:
`docs/canon/WFC_FLOW_METRICS.md`.

## Decisiones

- **El registro de datos es la fuente única.** Cada chunk es un grafo de plataformas en su
  marco local; las escenas y el arte se derivan de él, no al revés. Una escena que no
  coincida con el registro está mal.
- **Es una cadena 1D, no una rejilla WFC.** Todo chunk entra por socket `A` y su salida
  principal casa con el `A` del siguiente arrastrando un desplazamiento (`dy`, `bank_deg`).
  `A_High` y `A_Curved_15` no son tipos que exijan pareja: son ese desplazamiento.
  El peralte de `scaffold_curved_bank` es **solo visual para la ruta** (decisión del
  2026-11-15): la pasarela se inclina de verdad —malla y colisión— alrededor de su línea
  central con el perfil `roll_profile` (5-10-15-15-10-5°), pero entra y sale plana, así que
  el grafo, los waypoints y el socket de salida (`A`) son los de un tramo recto. No hay giro
  de rumbo ni ruta helicoidal.
  `WFCSolverCore` (rejilla 2D de losetas) sigue siendo el generador de `MachineBay` y de
  `ScaffoldStreamController`; no se reemplaza.
- **Los tamaños se derivan de las métricas** con las funciones de `FlowRouteValidator`, no
  se hardcodean: cambian solos con `g` (anillo centrífugo).
- Vive en `core_v2/systems/scaffold/`; no existe ni se crea `core_v2/wfc/`.

## Invariantes

- Todo chunk, solo, tiene ruta principal de `in` a `out` sin herramientas.
- En la ruta principal ningún hueco supera `0.70·D(Δh)` ni ningún desnivel `0.75·H_max`,
  a 60 Hz y a 30 Hz.
- Los sockets laterales `S` (estación) y `R` (riel) nunca están en la ruta principal.
- **Las barandas son dato del registro** (`rails` por nodo) porque tienen colisión: malla y
  caja salen de ahí. Toda plataforma lleva baranda en sus dos costados salvo hacia donde la
  ruta cruza de costado (una arista la une con una plataforma de ese lado) o donde el nodo
  declara `open_sides`.
- Un diorama siempre lleva pasarela peatonal `A → A` de paso.
- Un atajo de herramienta es **físicamente imposible a pie**: toda caja que lo cierra
  (`blockers`) mide `1.20·H_max` de alto. Un mamparo que se puede saltar no exige láser.
- Misma semilla ⇒ mismo grafo y mismos waypoints. El generador usa un LCG propio.
- El primer y el último chunk de un tramo son `scaffold_sprint_chute`.

## Desviaciones del brief original (pendientes de decisión de diseño)

- `scaffold_gloo_rise` sube `1.20·H_max`, no `+H_nom`: con `0.75·H_max` la pared se salta a
  pie y el gloo no haría falta.
- `scaffold_triple_cadence` usa huecos de ritmo (≤ `0.55·D`, hoy 2 m): tres huecos de
  `D_nom` no caben en 12 m.
- `scaffold_catenary_span` cruza 10 m (≈ `1.0·D`): un hueco `≥ 1.20·D` no cabe en un chunk
  de 12 m. Está marcado `requires_tool`, pero un roll-jump perfecto lo alcanza.
- `diorama_counterweight_crane` tenía solo salida `S`; se le agregó la pasarela `A`.

## Pipeline de arte

`tools/scaffold_chunks/build.sh` regenera todo: registro → `chunks.json` → Blender
(`scene_chunks.py`, skill `docs/skills/blender-bpy.md`) → GLB → `tools/bake_scaffold_chunks.gd`
→ `core_v2/props/scaffold/chunks/<id>.mesh` + `<id>.tscn`.

- Blender solo viste; las medidas las lee del JSON del registro. La **colisión** y los
  **sockets** de la escena los escribe el baker desde el registro, nunca desde la malla.
- Los GLB viven en `tools/scaffold_chunks/glb/` con `.gdignore` y se leen en runtime con
  `PackedSceneGLTF`: no hay artefactos `.import` ni GLB en el pck.
- Objetos de Blender con prefijo `Dyn_` van a `<id>_dyn.mesh` (nodo `Dyn`): son el lugar de
  los props dinámicos (mamparo cortable, cable, carro) y no se sueldan a la malla estática.
- `materials/M_*.tres` se crean solo si faltan: se afinan a mano y el rehorneado no los pisa.
- Blender nombra el material por función (`M_Grate`, `M_Frame`, `M_Panel`, …) y el baker
  escribe el material **del juego** para ese nombre, de la misma familia que
  `SteelGratePlatform` (rejilla con alpha scissor, triplanar local porque las cajas no traen
  UV a escala). Ningún metal por encima de ~0.6 de `metallic`: sin cielo ni ReflectionProbe
  sale negro.
- **Props reales:** un `blocker` con `cuttable` se hornea como `LaserGate` (dueño de su
  panel: el chunk solo trae el marco); un `span` del registro se hornea como `GlooSpan` con
  `span_is_local`. La pared de `gloo_rise` no lleva prop: los blobs de gloo curados ya
  hacen de escalera sobre una pared estática. `GlooSpan` solo tiende puentes horizontales.
- El pórtico de junta va solo en la entrada (`z = 0`) de cada chunk y es solo visual.
- Cada escena: `Mesh`, `Dyn` (si hay), `Collision/Col_<nodo>`, `Blocker_<id>/Col`,
  `Socket_In_A`, `Socket_Out_<tipo>` y metadata `sockets`.
- Una rampa se declara con `rise` en el nodo y **se entra por su pie** (`ramp_foot`): de
  costado es una pared.
- Cambiar una medida = editar el registro y correr `build.sh`. `test_scaffold_chunk_scenes`
  falla si una escena quedó desfasada.

## Pendiente

- Cable, carro y grúa (`Dyn_*`) siguen siendo malla estática: falta cablear la cuerda y el
  carro reales.
- Consumidor en runtime (streaming de un tramo por semilla dentro de un nivel).

## Proyección orbital

`core_v2/systems/scaffold/ScaffoldChunkOrbit.gd` coloca un tramo sobre el interior de un
cilindro (marco del nodo: eje = X, arco = Z, subir = hacia el eje).

- La física del jugador no cambia (`Vector3.UP`, `AGENTS.md` §5.1): se recoloca el mundo. El
  tramo bajo el jugador queda plano y el resto se curva, igual que `CylinderRotator`.
- **Dos espacios:** plano (el del registro: grafo, waypoints) y físico (donde están los
  cuerpos). Coinciden en el punto bajo el jugador. Todo lo que razona sobre la ruta lo hace
  en plano; `world_to_flat` / `flat_to_world` convierten.
- Cada chunk es rígido y se apoya como cuerda del círculo a **su** radio (`base_radius −
  altura`): las juntas calzan aunque el tramo suba o baje.
- El estado sale solo de la posición del jugador: no necesita snapshot de replay.
- No ajusta la gravedad al radio: los tamaños del registro siguen calculados con el `g` del
  piloto, no con `g_eff = ω²·r`.

## Kit de fondo del entrecasco

`tools/scaffold_chunks/scene_hull.py` → `core_v2/props/hull_underdeck/*.mesh` (vano de casco,
envés de terraza, pilón). Son solo malla: no llevan medidas de juego. El nivel
`core_v2/levels/hull_underdeck/HullUnderdeck.tscn` cuelga un vano de cada chunk, estirado al
arco que ocupa a **su** radio (`radio_del_vano / radio_del_chunk`) para que los vanos calcen,
y le da colisión solo al forro del casco. Visión del lugar: `product/entrecasco.md`.

## Escena de prueba

`core_v2/levels/scaffold_run/ScaffoldRunLab.tscn` arma un tramo por semilla (`seed_value`,
`chunk_count`, `orbit_radius` para proyectarlo al cilindro; `SCAFFOLD_LAB_RADIUS=<m>` lo
fuerza) con las escenas horneadas y suelta al piloto con el modo asistido activo.
`SCAFFOLD_LAB_SHOTS=1` guarda capturas desde la cámara del jugador en
`test_output/scaffold_run/` y cierra; durante esa corrida no hay que tocar los controles
(cualquier input interrumpe al piloto automático).
