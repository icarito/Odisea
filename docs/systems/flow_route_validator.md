# FlowRouteValidator (Transit-Run · Pista C)

Módulo de datos puro y determinista (`core_v2/systems/flow/FlowRouteValidator.gd`, `extends Reference`) para validar rutas de parkour cinético sin instanciar escenas.

## Propósito

Garantizar que cualquier grafo de plataformas o chunks tenga al menos una **ruta principal** de entrada a salida calibrada al **≤ 80%** del alcance real del jugador corriendo por defecto (`v_run = 7`, `g = 14`, `v_jump = 10`, `H_max ≈ 3.6 m`, `D_max ≈ 10 m`), sin requerir herramientas (`GlooClimb`, `MagRail`), puzles ni estaciones `CuratedSocket` (que quedan como Side Sockets opcionales), y clasificando tramos exigentes (`90–100%`, roll-jump) como opcionales.

## Fórmulas implementadas

Con corrección por paso discreto de simulación semi-implícito (`+v · dt / 2`):

- **Altura máxima:**
  `H_max = v_jump² / (2g) + 0.5 · v_jump · tick`
- **Tiempo en el aire para un desnivel `Δh`:**
  `t_aire(Δh) = (v_jump + √(v_jump² - 2gΔh)) / g` (retorna `-1.0` si `v_jump² - 2gΔh < 0`)
- **Alcance horizontal máximo:**
  `D(Δh) = v_run · t_aire(Δh) + 0.5 · v_run · tick`

## Contrato de entrada/salida

- `FlowRouteValidator.validate(graph: Dictionary, metrics: Dictionary = {}) -> Dictionary`
  - `graph`: `{ "entry": String, "exit": String, "nodes": Array[Dictionary], "edges": Array[Dictionary] }`
    - Nodos: `id`, `position` (`Vector3` o `[x,y,z]`, opcional si la arista trae `gap_horizontal`/`delta_h`), `size` (opcional), `tags` (`SprintGap`, `RhythmSteps`, `GlooClimb`, `MagRail`, `CuratedSocket`), `g` (opcional, p.ej. anillo centrífugo `g(r)`).
    - Aristas: `from`, `to`, `gap_horizontal` (o `gap`), `delta_h` (o `dh`), `tags`, `requires_tool`, `is_socket`, `g` (opcional por tramo).
  - `metrics`: `{ "g", "v_run", "v_jump", "tick", "main_threshold", "optional_min", "optional_max" }`.
    - Incluye `FlowRouteValidator.metrics_from_object(flow_metrics)` para construir el diccionario desde `core_v2/systems/flow/FlowMetrics.gd` cuando aterrice en `main`.
  - Retorno: `valid_main_route`, `main_path`, `edges_evaluated`, `optional_edges`, `tool_edges`, `unreachable_edges`, `critical_edge`, `report`.

## Consumidores previstos

1. **`MachineBayLabyrinthStreamer`** (`core_v2/levels/machines/MachineBayLabyrinthStreamer.gd`): valida la conectividad de costuras entre chunks generados (`SprintGap` / `RhythmSteps`) y confirma que las ramas `CuratedSocket` permanezcan opcionales.
2. **`bay_vertical`**: valida rutas de ascenso vertical con gravedad local variable `g(r)` por tramo y separa atajos `MagRail` / `GlooClimb` de la ruta principal.

Ver ejemplos ejecutables en `core_v2/tests/test_flow_route_validator.gd`.
