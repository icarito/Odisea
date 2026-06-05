# FD-052: ANNA Performance Profiling Bridge

**Status:** Design
**Priority:** High
**Effort:** Small
**Created:** 2026-06-05
**Completed:** -

## Problem

ANNA MCP ya expone algunos datos de rendimiento en `odisea://simulation/telemetry`, pero son insuficientes para diagnosticar los problemas reales:

- **Runtime:** caídas de FPS al generar chunks del ScaffoldStream, LOD switching
- **Startup:** tiempo de carga de escenas, inicialización de sistemas
- **Transiciones:** SCENE command, carga de recursos entre niveles

Claude intenta perfilar pero con solo `fps` + `process_ms` + `physics_ms` no puede aislar si el cuello de botella es GPU (draw calls, vértices), CPU (lógica, física), o memoria (leaks, fragmentación).

Además, no hay herramienta de profiling session que capture N frames y devuelva min/max/avg/p99 — Claude tiene que muestrear manualmente frame a frame.

## Current state (qué YA existe)

`get_simulation_telemetry_resource()` en AnnaInterface.gd ya expone:

| Campo | Fuente | Presente |
|-------|--------|----------|
| `fps` | `Performance.TIME_FPS` | ✅ |
| `process_ms` | `Performance.TIME_PROCESS` | ✅ |
| `physics_ms` | `Performance.TIME_PHYSICS_PROCESS` | ✅ |
| `draw_calls` | `Performance.RENDER_DRAW_CALLS` | ✅ (con null check) |
| `node_count` | `Performance.OBJECT_NODE_COUNT` | ✅ (con null check) |
| `elias` | Player position/velocity | ✅ |
| `hardware` | Driver, headless, shadows | ✅ |

También en `_get_metrics()` (usado por RL, NO por telemetry):
- `mem_static`: `OS.get_static_memory_usage()`
- `objects`: `Performance.OBJECT_COUNT`

## Solution

### Phase 1 — Extender telemetry (1 archivo, ~15 líneas)

Agregar a `get_simulation_telemetry_resource()` en `AnnaInterface.gd`:

```gdscript
# Render detail
"render_objects": _safe_monitor("RENDER_OBJECTS_IN_FRAME"),
"render_vertices": _safe_monitor("RENDER_VERTICES_IN_FRAME"),
"render_material_changes": _safe_monitor("RENDER_MATERIAL_CHANGES_IN_FRAME"),

# Physics load
"physics_3d_active": _safe_monitor("PHYSICS_3D_ACTIVE_OBJECTS"),

# Memory
"memory_static_mb": _safe_monitor("MEMORY_STATIC"),
"memory_dynamic_mb": _safe_monitor("MEMORY_DYNAMIC"),

# Frame breakdown (CPU vs GPU)
"idle_ms": _safe_monitor("TIME_IDLE") * 1000.0,     # GPU wait
```

Agregar helper en AnnaInterface.gd:

```gdscript
func _safe_monitor(name: String) -> int:
    if Performance.get(name) != null:
        return int(Performance.get_monitor(Performance[name]))
    return -1
```

### Phase 2 — Profiling session tool (~30 líneas en AnnaBridge.gd)

Nueva tool MCP: `profile_session`

Parámetros:
```json
{
  "duration_frames": 120,
  "sample_every_n_frames": 1
}
```

Respuesta:
```json
{
  "frames_sampled": 120,
  "duration_s": 2.0,
  "fps": {"min": 42, "max": 60, "avg": 55.3, "p99": 58.0},
  "process_ms": {"min": 2.1, "max": 18.5, "avg": 4.2, "p99": 12.0},
  "physics_ms": {"min": 1.2, "max": 22.0, "avg": 3.1, "p99": 15.0},
  "draw_calls": {"min": 45, "max": 320, "avg": 120},
  "render_vertices": {"min": 8000, "max": 45000, "avg": 18000},
  "render_objects": {"min": 120, "max": 850, "avg": 340},
  "node_count": {"min": 450, "max": 520, "avg": 480},
  "memory_static_mb": 245,
  "memory_dynamic_mb": 68,
  "frames_below_60fps": 12,
  "bottleneck_suspect": "physics"   // heurística: qué métrica tiene más varianza
}
```

### Phase 3 — Scene transition timer (OYS + ANNA)

Ya se puede hacer con OYS hoy:
```oys
SET t0 TIME
SCENE Dome_Crio
WAIT 30
SET t1 TIME
EVAL $t1 - $t0
PRINT Transicion: $ans segundos
```

Faltaría que ANNA lo exponga como tool MCP: `time_scene_load {"scene": "Dome_Crio"}` que:
1. Registra el tiempo actual
2. Ejecuta `get_tree().change_scene(scene_path)`
3. Espera `_ready()` del root de la nueva escena
4. Devuelve `load_time_ms`

Pero esto es más complejo porque el bridge se desconecta durante el cambio de escena. → **Deferir a post-MVP.**

## Considered Options

- **Phase 1 only:** Extender telemetry con los monitores faltantes. Claude ya tiene los datos, solo le falta granularidad GPU/CPU/memoria. **Seleccionada como MVP inmediato.**
- **Phase 1+2:** Añadir profiling session tool. Requiere un buffer circular en AnnaBridge.gd para acumular frames. **Útil pero no urgente.**
- **Phase 1+2+3:** Scene transition timer. Complejo por la desconexión del bridge durante cambio de escena. **Post-MVP.**

## Files to Modify

| Archivo | Cambio | Phase |
|---------|--------|-------|
| `core_v2/anna/AnnaInterface.gd` | Agregar monitores a telemetry + helper `_safe_monitor()` | 1 |
| `core_v2/anna/AnnaBridge.gd` | Agregar tool `profile_session` + buffer circular | 2 |
| `core_v2/anna/client/odisea_mcp_stdio_server.py` | Agregar tool schema `profile_session` | 2 |

## Verification

1. `bridge_launch` → `odisea://simulation/telemetry` debe incluir `render_vertices`, `memory_static_mb`, etc.
2. Caminar por la scaffold con muchos chunks → `physics_ms` debe subir detectablemente
3. `profile_session {"duration_frames": 60}` → debe devolver min/max/avg/p99 para todas las métricas
4. Los campos nuevos deben ser `-1` si el monitor no existe (compatibilidad con distintas builds de Godot)
