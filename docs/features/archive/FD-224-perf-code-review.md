# FD-224: Performance Code Review — Low Hanging Fruit

**Status:** Open
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-16
**Completed:** -

## Objective

Realizar un **code review orientado a performance** de todo el proyecto Odisea (`core_v2/`), identificando **low hanging fruit** (oportunidades de mejora rápidas con alto impacto) e implementándolas directamente.

El review debe priorizar hallazgos que:

1. Reduzcan frame drops en escenas complejas (Dome_Crio, ScaffoldOrbit)
2. Disminuyan tiempos de carga / import de recursos
3. Optimicen el uso de memoria en runtime
4. Eliminen work redundante en _process/_physics_process
5. Mejoren la eficiencia de ANNAV2 telemetry (HTTPS calls, serialización)
6. Reduzcan draw calls / overdraw en niveles

## Scope

Revisar **todo el código fuente en `core_v2/`** más los scripts Godot en la raíz. GDScript 1.x (Godot 3), priorizando:

- `core_v2/actors/` — PlayerController, CargolController
- `core_v2/levels/interiors/` — Dome_Crio y sus scripts
- `core_v2/levels/facades/` — DomeFacade y scaffolds
- `core_v2/components/` — componentes reutilizables
- `core_v2/systems/` — gas, world rotator, etc
- `core_v2/telemetry/` — ANNAV2, hotzones
- `core_v2/input/` — InputProviderV2
- `core_v2/tools/` — HotzonePlayer
- Scripts raíz: `runbin.sh`, `runtest.sh`, `replay.sh`

## Methodology

Para cada archivo revisado, evaluar:

1. **Llamadas en _process()** — ¿algo que no necesita correr cada frame? (set_process(false) cuando inactivo, timers en vez de polling)
2. **Instanciación dinámica** — ¿preload() vs load()? ¿Pool de objetos?
3. **Señales vs polling** — ¿get_node() repetido? ¿usar @onready en su lugar?
4. **Cálculos redundantes** — ¿valores que se recalculan cada frame y podrían cachearse?
5. **Memoria** — ¿recursos que se cargan y nunca se liberan? ¿referencias circulares?
6. **Draw calls** — ¿mallas sin combinar? ¿materiales duplicados?
7. **ANNAV2** — ¿envíos HTTP demasiado frecuentes? ¿JSON serialización pesada?
8. **Import de assets** — ¿formatos de textura/mesh ineficientes?

## Output

- Cada hallazgo documentado como comentario en el código (`# PERF: ...`)
- Implementación directa de los fixes de bajo riesgo (cambios triviales: renombrar, mover, cachear)
- Para cambios estructurales grandes: dejar TODO comentado y mencionarlo en el summary

## Files to Modify

Los que resulten del review. Sin archivos nuevos — solo modificar existentes.

## Verification

1. El juego carga y corre sin errores (smoke test)
2. FPS en Dome_Crio no baja respecto al main actual
3. Los cambios de performance no alteran comportamiento visible (determinismo preservado)
4. Los tests OYS en CI siguen pasando
