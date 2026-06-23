# FD-239: Reconciliación de Documentación — Feature Docs vs Implementación

**Status:** Open
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-23
**Completed:** -

## Problem

Varios Feature Docs (FDs) del proyecto tienen estados desactualizados: algunos marcan "Planned" o "In Progress" cuando su implementación ya está completa. Otros FDs implementados ni siquiera aparecen en el FEATURE_INDEX. Además, algunas features recién implementadas necesitan revisión Q/A, pulido, o documentación complementaria que nunca se escribió.

Esto genera confusión sobre qué está realmente hecho, qué falta, y qué necesita atención.

## Solution

Reconciliar el estado real de cada FD contra su documentación. Para cada FD:

1. **Si está implementado pero el FD dice otra cosa:** actualizar status, añadir notas de implementación (commits relevantes, fecha estimada de finalización), y mover al backlog correcto.
2. **Si está implementado pero necesita Q/A o pulido:** marcar como "Pending Verification" y agregar una sección de "Known Issues / Gaps" en el FD que documente qué falta.
3. **Si está implementado pero subdocumentado:** escribir o mejorar la sección de "Verification" y añadir referencias cruzadas a scripts y escenas relevantes.
4. **FEATURE_INDEX:** actualizar todas las entradas para que reflejen el estado real.

### FD Inventory — Estado Real vs Documentado

| FD | Título | Status en FD | Status Real | Acción |
|----|--------|-------------|-------------|--------|
| FD-027 | Spawn Cinematic / Death Blink | In Progress | Implemented | Update status + Q/A |
| FD-032 | Seamless Startup Streaming | In Progress | Implemented | Update status |
| FD-034 | Player Interaction Hints | Planned | Implemented | Update status |
| FD-035 | ConveyorCarrousel | Design | Implemented | Update status |
| FD-036 | Gravity Manager | Implemented / In Progress | Implemented | Clean status |
| FD-038 | ZeroGravityController | Design / Prototype | Implemented (FD-233) | Update status |
| FD-040 | PlateContentStream Stability | Verified / In Progress | In Progress | Keep — verify status |
| FD-043 | RadialScatter | Implemented | Implemented | OK |
| FD-044 | Pipe Valve Props | Design | Design | Probablemente listo? Verificar |
| FD-045 | Gas Simulation | Design | Design | Verificar |
| FD-049 | Zero-G Camera Rig | Design | Design | Verificar |
| FD-051 | Prop Visualizer Skill | In Progress | Implemented | Update status |
| FD-053.1 | Airlock Test | Spec | Implemented | Update status |
| FD-053 | AirlockManager | Design | Design | Verificar |
| FD-214 | Runbin HTML5 | (not in index) | Implemented | Add to index + update |
| FD-224 | Perf Code Review | (not in index) | Implemented | Add to index + update |
| FD-227 | Signage Panels | (not in index) | Naive implementation | Add to index + Q/A + refine |
| FD-231 | Main Menu & Pause | (not in index) | Implemented | Add to index + polish notes |
| FD-232 | FireEmitter Fix | (not in index) | Implemented | Add to index |
| FD-233 | ZeroG Inertia Layer | (not in index) | Implemented | Add to index |
| FD-234 | Version Display | (not in index) | Implemented | Add to index |
| FD-235 | Performance Pass | (not in index) | Implemented | Add to index |
| FD-236 | Bake Airlock CSG | (not in index) | Implemented | Add to index |
| FD-237 | Async Scene Loading | (not in index) | Implemented | Add to index |

### Prioridad de Acción

**P1 — Q/A y refinamiento:**
- **FD-227 Signage Panels**: implementación naíf, necesita: (a) probar en escena real, (b) decidir si text-based o icon-based, (c) alineación con el arte del módulo Criogenia
- **FD-231 Main Menu & Pause**: funcional pero pulible — revisar gamepad navigation, transition smoothness, versión/fecha display
- **FD-027 Spawn Cinematic**: falta documentación de cómo se activa, qué parámetros usa, y cómo testearlo en editor

**P2 — FEATURE_INDEX + Status Updates:**
- Los FDs marcados como "Add to index" + "Update status" en la tabla

**P3 — Documentación faltante:**
- Gravity Manager (FD-036): subdocumentado — flujo de gravedad por zona, interacción con WorldRotator
- Spawn Cinematic (FD-027): secuencia de activación, eventos, overlays

## Files to Modify

- `docs/features/FEATURE_INDEX.md` (tabla principal)
- `docs/features/FD-027_spawn_cinematic.md` (status + doc)
- `docs/features/FD-032_seamless_startup_streaming.md` (status)
- `docs/features/FD-034_player_hints.md` (status)
- `docs/features/FD-035_conveyor_carrousel.md` (status)
- `docs/features/FD-036_gravity_manager.md` (status + doc)
- `docs/features/FD-038_zero_gravity_controller.md` (status)
- `docs/features/FD-040_plate_content_stream_stability.md` (verify status)
- `docs/features/FD-051_prop_visualizer_skill.md` (status)
- `docs/features/FD-053_dome_crio_airlock_test.md` (status)
- `docs/features/FD-214-runbin-html5.md` (status + add to index)
- `docs/features/FD-224-perf-code-review.md` (status + add to index)
- `docs/features/FD-227-signage-panels.md` (Q/A section + index)
- `docs/features/FD-231-main-menu-and-pause.md` (Q/A section + index)
- Posiblemente: `docs/features/FD-232.md` a `FD-238.md` (crear entries y añadir a index)

## Verification

1. `FEATURE_INDEX.md` tiene todas las entradas correctas y consistentes
2. Cada FD reconciliado tiene status actualizado y nota de implementación
3. FDs con Q/A pendiente tienen sección "Known Issues" o "Pending" clara
4. Ningún FD queda marcado "Planned" o "In Progress" si ya está en main
