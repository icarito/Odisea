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
- Un diorama siempre lleva pasarela peatonal `A → A` de paso.
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
- El pórtico de junta va solo en la entrada (`z = 0`) de cada chunk y es solo visual.
- Cada escena: `Mesh`, `Dyn` (si hay), `Collision/Col_<nodo>`, `Blocker_<id>/Col`,
  `Socket_In_A`, `Socket_Out_<tipo>` y metadata `sockets`.
- Una rampa se declara con `rise` en el nodo y **se entra por su pie** (`ramp_foot`): de
  costado es una pared.
- Cambiar una medida = editar el registro y correr `build.sh`. `test_scaffold_chunk_scenes`
  falla si una escena quedó desfasada.

## Pendiente

- Los `Dyn_*` y los `Blocker_*` cortables son malla y caja estáticas: falta cablearlos a los
  props reales (`LaserGate`, `GlooSpan`, cuerda, carro).
- Proyección al cilindro de `ScaffoldOrbit` y uso de `bank_deg`.
- Consumidor en runtime (streaming de un tramo por semilla dentro de un nivel).

## Escena de prueba

`core_v2/levels/scaffold_run/ScaffoldRunLab.tscn` arma un tramo por semilla (`seed_value`,
`chunk_count`) con las escenas horneadas y suelta al piloto con el modo asistido activo.
`SCAFFOLD_LAB_SHOTS=1` guarda capturas desde la cámara del jugador en
`test_output/scaffold_run/` y cierra; durante esa corrida no hay que tocar los controles
(cualquier input interrumpe al piloto automático).
