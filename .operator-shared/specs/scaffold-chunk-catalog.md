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

## Pendiente

- Escenas `.tscn` de los 10 chunks (Godot 3: `CollisionShape` + `Position3D` para sockets).
- Proyección al cilindro de `ScaffoldOrbit` y uso de `bank_deg`.
- Consumidor en runtime (streaming) y ruta para `AutopilotInputV2`.
