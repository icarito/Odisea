# FD-050 — Pasarelas y Andamios Procedurales (WFC 2D)

**Status:** En desarrollo — WFC funcional, pulido visual avanzado  
**Scope:** Acto I — Gap casco-espirales  
**Branch:** `fd-050-scaffold-wfc-17347442582962886612` (PR #95)  
**Relacionado:** FD-037 (Infinite Scaffold Field)

---

## Visión general

Generador procedural de redes de pasarelas y andamios usando Wave Function Collapse sobre grilla 2D. Los módulos son instancias de `SteelGratePlatform` con dimensiones, rails y alturas paramétricas.

## Catálogo (9 módulos)

| ID | Tipo | Tamaño | Conexiones | Altura |
|----|------|--------|-----------|--------|
| W | Walkway | lane × cell | N-S o E-O | plano |
| R | Railing | lane × cell | N-S o E-O c/barandas | plano |
| P | Platform | cell × cell | 4 direcciones | plano |
| S | Stairs | lane × cell | N-S o E-O | +2m en un extremo (port_heights) |
| C | Curve | lane × lane | Esquina 90° | plano (rampa solo en modelo WFC) |
| G | Gap | lane × cell | N-S o E-O, abertura | plano |
| X | Cross | lane × lane | 4 direcciones | plano, rails 4 lados + openings |
| T | T-Junction | lane × lane | 3 direcciones | plano, rails 4 lados + openings |
| E | End | cell × cell | Terminal 1 dir | plano |

> `lane = clamp(cell_size * 0.32, 2.5, 4.5)` (~3.2m con cell_size=10)

## Estado actual (2026-06-01)

### ✅ Resuelto
- **Soportes flotantes:** Todas las patas llegan a world y=0 usando `support_base_local_y = deck_local_y - state.base_height`
- **Altura de deck correcta:** `translation.y = state.base_height - deck_local_y` compensa `platform_height=1.6`
- **Rails en X/T:** `_apply_intersection_rails` → rails ON en 4 lados. `_apply_opening_widths_from_connections` → openings = lane en lados conectados
- **X/T/C compactos:** Usan `_lane_width()` (~3.2m) en vez de `cell_size` (10m)
- **Stairs altura correcta:** `_apply_port_heights_to_front_back` usa port_heights del WFC (single-axis ±2m)
- **Collision + mesh stairs:** Slope scaling (`1/cos(slope_angle)`) en deck y collision shape
- **C ramps WFC:** 8 variantes C con port_heights ±2m permiten transiciones de altura en esquinas en el modelo

### ⚠️ Limitaciones conocidas
- **C curvas sin tilt visual:** SteelGratePlatform solo inclina en eje front-back. C módulos son visualmente planos aunque el WFC modele rampas en esquinas.
- **Islas desconectadas:** El WFC puede generar componentes de altura inconsistente si `min_height_span` es bajo. Subir `min_height_span` o `min_elevated_cells` fuerza más cohesión.
- **Sin solapamiento visual:** Módulos adyacentes no solapan geometría — los decks terminan exactamente en el borde de la celda.
- **C sin geometría curva:** El módulo C es una plataforma cuadrada, no una pieza curva real.

### 🔜 Próximos pasos recomendados
1. **Solapamiento opcional:** Añadir `cell_overlap_margin` (0.2-0.5m) para que decks de módulos adyacentes se toquen
2. **C con geometría real:** Modelar una pieza curva (L-shaped) en vez de plataforma cuadrada
3. **C con tilt:** Añadir `left_height_offset`/`right_height_offset` a SteelGratePlatform para tilt en eje width
4. **Stairs con mesh de escalones:** En vez de plano inclinado, generar escalones visibles cada 0.3-0.5m
5. **Balance de pesos:** Ajustar `weight_W` más alto para más walkways, reducir C/E
6. **Visual debug:** Modo wireframe o labels con altura de cada celda para debug

## Archivos

| Archivo | Rol |
|---------|-----|
| `core_v2/systems/ScaffoldWFCGenerator.gd` | WFC solver + instanciación (433 líneas) |
| `core_v2/props/scaffold/ScaffoldWalkway.tscn` | Módulo W |
| `core_v2/props/scaffold/ScaffoldRailing.tscn` | Módulo R |
| `core_v2/props/scaffold/ScaffoldPlatform.tscn` | Módulo P |
| `core_v2/props/scaffold/ScaffoldStairs.tscn` | Módulo S |
| `core_v2/props/scaffold/ScaffoldCurve.tscn` | Módulo C |
| `core_v2/props/scaffold/ScaffoldGap.tscn` | Módulo G |
| `core_v2/props/scaffold/ScaffoldCross.tscn` | Módulo X |
| `core_v2/props/scaffold/ScaffoldTJunction.tscn` | Módulo T |
| `core_v2/props/scaffold/ScaffoldEnd.tscn` | Módulo E |
| `core_v2/tests/test_scaffold_wfc.tscn` | Escena de test |
| `core_v2/tests/test_scaffold_wfc.oys` | Script OYS |

## Parámetros exportados (inspector)

- `grid_width` (4-32), `grid_depth` (2-12), `cell_size` (4-30)
- `weight_W` a `weight_E` + `weight_empty`
- `map_seed`, `debug_verbose`, `trigger_generate`

## Notas Godot 3

- `SteelGratePlatform.gd` acepta `platform_width`, `platform_depth`, `rail_front/back/left/right`, `front_height_offset`, `back_height_offset`, `rail_front/back_opening_width`
- Los módulos son escenas con script `SteelGratePlatform.gd`
- `_rebuild()` regenera la malla después de cambiar parámetros
