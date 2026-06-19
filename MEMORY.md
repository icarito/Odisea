# Project Memory Index — Odisea

> Índice de memorias del proyecto (tipo `project` y `reference`). Cada entrada es un archivo
>Markdown con hallazgos/contratos para futuras sesiones. Mantener alfabético.

## Project
- `docs/performance/project_airlock_exterior_hotzone.md` — hotzone del airlock y domo exterior (telemetría ANNAV2). Cruzar airlock cuesta ~8 fps de mediana; Dome_Crio celda (0,24) @ 16 fps/72 % low; OdiseaExterior FPS desploma caminando hacia +X al campo de domos. Gap de instrumentación `perf.dc/vtx/obj` resuelto (persistencia en SQLite + heatmap). Wins candidatos ordenados por evidencia.

## Reference
- _(pendiente)_ `reference_visualserver_render_info` — usar `INFO_OBJECTS_IN_FRAME` + `INFO_2D_ITEMS_IN_FRAME`; las constantes `*_DRAWS_IN_FRAME` no existen en 3.6. Referenciado en `docs/performance/performance_analysis.md`.

## Enlaces relacionados (memorias referenciadas pero no creadas aún)
- `project_exterior_perf` — FPS bajo en exterior era draw calls, no vértices.
- `project_exterior_clip_through` — snap de suelo en terraza móvil (anti clip-through).
- `project_perf_zone_rescan` — scan de grupo CameraZone throttleado.
