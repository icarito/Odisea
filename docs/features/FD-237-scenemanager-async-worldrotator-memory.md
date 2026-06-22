# FD-237 — Performance: SceneManager async + WorldRotator throttle + memoria Dome_Crio

## Problema

Tres fuentes de costo CPU/memoria identificadas por telemetría:

1. **SceneManager.gd:195** — `resource.instance()` es síncrono. Crea todos los nodos de la escena destino en un frame al cruzar el airlock → pico de CPU/alloc. Props pesados ya se difieren (`deferred_build`), pero la instanciación base sigue siendo bloqueante.

2. **WorldRotator.gd:1782** — pool de 32 StaticBodies sincronizado cada frame. El comentario interno dice "pool per-frame disparó CPU".

3. **Dome_Crio = 101 MB avg** — la escena más pesada en memoria. Posibles fugas: texturas sin `resource_local_to_scene`, meshes CSG no liberados, cache de domos retenido tras salir.

## Scope

### 1. SceneManager — diferir instanciación base

- Perfilar `resource.instance()` para Dome_Crio y OdiseaExterior (cuánto tarda en ms)
- Si > 16ms: diferir la creación de nodos en chunks de N nodos/frame
- Usar `call_deferred` o un contador en `_process` para distribuir la instanciación
- Priorizar nodos visibles primero (los que están en el frustum)
- Mantener compatibilidad con `deferred_build`

### 2. WorldRotator — throttlear sync

- Cambiar el sync de pool de cada frame a cada N frames (N=3 o configurable)
- Medir reducción de CPU en perfilado
- Verificar que la rotación sigue siendo fluida visualmente

### 3. Memoria Dome_Crio — diagnosticar y reducir

- Identificar qué ocupa los 101 MB:
  - Texturas: revisar `resource_local_to_scene` en props repetidos
  - Meshes: ¿CSG runtime generando copias?
  - Cache: ¿referencias a escenas/recursos no liberados al salir?
- Usar `Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)` y `Performance.OBJECT_NODE_COUNT`
- Target: < 80 MB (reducción 20%)

### 4. Verificación con telemetría

- Antes/después de SceneManager: medir el tiempo de swap del airlock
- Antes/después de WorldRotator: medir CPU time en `_process`
- Antes/después de memoria: medir `memory_mb` en ghosts de Dome_Crio

## Archivos

| Archivo | Acción |
|---------|--------|
| `core_v2/autoloads/SceneManager.gd` | Diferir instanciación |
| `core_v2/systems/WorldRotator.gd` | Throttlear sync |
| `core_v2/props/doors/AirlockChamber.tscn` | Revisar memory leaks |
| `core_v2/levels/interiors/Dome_Crio.tscn` | Revisar memory leaks |

## Verificación

- Swap de airlock: sin freeze perceptible (< 16ms por frame)
- WorldRotator: CPU time reducido sin artefactos visuales
- Memoria Dome_Crio: < 80 MB
- No regresión funcional (airlock, rotación, carga de escenas)

## Out of scope

- No modificar OdiseaExterior (lo cubre FD-235 Jules D)
- No cambiar la arquitectura de carga de escenas
- No tocar el sistema de deferred_build existente
