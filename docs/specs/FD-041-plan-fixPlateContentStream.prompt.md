# Plan: Fix FD-040 PlateContentStream + BaseTerrace integration

## TL;DR
Tres bugs concretos + una feature de autoría. El bug principal es que `_refresh_active_slots()` destruye y recrea contenidos al reasignar slots (sort inestable). Eso causa el "objetos desaparecen" y también el jitter (recreación en MODE_RIGID). Los fixes son: (1) sticky slot assignment, (2) preservar estado de RigidBody en slot save/restore, (3) suavizar visual_push_correction, (4) crear PlateSlotConfig para authoring en inspector.

---

## Phase 1: Fix sticky slot assignment ("objetos desaparecen")

**Problema:** `_refresh_active_slots()` en `PlateContentStream.gd` ordena candidatos por distancia. Cuando el orden cambia, una asignación que antes usaba slot[0] ahora usa slot[2] → `_activate_slot` detecta `not same_key` → `_clear_slot_children` → destruye cajas.

**Fix:** Cambiar `_refresh_active_slots()` para ser sticky:
1. Primero, de los slots ya activos, mantener los que siguen siendo candidatos (aunque cambien de posición en el ranking)
2. Solo reasignar slots que quedan libres a nuevos candidatos que no tengan slot
3. Solo liberar un slot si su key ya no está en los candidatos activos

Archivo: `core_v2/systems/PlateContentStream.gd`
- Método `_refresh_active_slots()` — cambiar lógica de "sort and fill" a "preserve existing, fill gaps"
- Añadir método auxiliar `_find_slot_for_key(key) -> int` que busca slot activo por key

## Phase 2: Fix RigidBody state preservation al re-activar slot

**Problema:** Cuando un slot se activa de nuevo (jugador regresa a terraza), la escena se instancia desde cero. Las cajas empiezan en `MODE_RIGID` y necesitan `settle_frames` para estabilizarse. Además hay un bug en `PlateContentPushBoxes.gd`: el loop de `_settle_pushables()` usa `body` en vez de `child` como variable — las cajas nunca se pre-settlan.

**Fix en `PlateContentPushBoxes.gd`:** corregir bug `body` → `child` en el loop.

Archivo: `core_v2/tests/PlateContentPushBoxes.gd`

## Phase 3: Suavizar visual_push_correction (clipping de manos)

**Problema:** `visual_push_correction` se calcula directo de `surf_dist` cada frame sin lerp. Cuando la caja jitter, la corrección visual salta abruptamente.

**Fix:** En `PlayerControllerV2.gd`, aplicar lerp a `visual_push_correction`:
- Añadir var `_push_correction_smoothed: float = 0.0`
- En `_update_push_state`: calcular raw correction, luego `_push_correction_smoothed = lerp(_push_correction_smoothed, raw_correction, 15.0 * dt)`
- Usar `_push_correction_smoothed` en lugar de `visual_push_correction` en el IK de manos

Verificar dónde se usa `visual_push_correction` en el sistema de animación/IK (buscar en `PilotAnimatorV2.gd` o similar).

Archivo: `core_v2/player/PlayerControllerV2.gd`

## Phase 4: PlateSlotConfig — authoring en Inspector

**Feature:** Permitir asignar escenas a placas directamente en el Inspector de Godot mediante nodos hijo del `PlateContentRoot`.

**Implementación:**
1. Crear `core_v2/systems/PlateSlotConfig.gd`:
   - Extends `Node` (no Spatial — no tiene representación visual)
   - `export(int) var spiral_idx := 0`
   - `export(int) var plate_idx := 0`
   - `export(PackedScene) var content_scene`

2. Modificar `PlateContentStream._ready()`:
   - Después de `_build_slot_pool()`, escanear children de `self` que sean `PlateSlotConfig`
   - Para cada uno, llamar `assign_scene(cfg.spiral_idx, cfg.plate_idx, cfg.content_scene)`

3. Añadir uno o más `PlateSlotConfig` como hijos de `PlateContentRoot` en `BaseTerrace.tscn` (via editor o .tscn edits)

Archivos a crear: `core_v2/systems/PlateSlotConfig.gd`
Archivos a modificar: `core_v2/systems/PlateContentStream.gd` (3 líneas en `_ready`)

## Phase 5: Verificación + Tests

**Pruebas interactivas:**
1. `./runtest.sh --show --oys test_push_integration` — push básico sigue funcionando
2. Abrir TestWorldRotator.tscn en Godot → caminar entre terrazas → verificar que cajas NO desaparecen
3. Empujar caja en TestWorldRotator → verificar que no jitter y manos no clipean
4. Abrir BaseTerrace.tscn → añadir PlateSlotConfig hijo de PlateContentRoot en Inspector → verificar que la escena aparece en esa terraza

**Tests automatizados:**
```bash
./runtest.sh -a ./core_v2/tests/test_world_rotator.gd
./runtest.sh -a ./core_v2/tests/test_plate_content_stream.gd
./runtest.sh -a ./core_v2/tests/  # regresión completa antes de merge
```

## Phase 6: Commit + Push

- Commit 1: "fix(PlateContentStream): sticky slot assignment prevents content destruction on sort reorder"
- Commit 2: "fix(PlateContentPushBoxes): correct settle_pushables loop var name"
- Commit 3: "fix(PlayerController): smooth visual_push_correction to reduce hand clipping"
- Commit 4: "feat(PlateSlotConfig): inspector-based plate content authoring"
- Push branch → PR ya existente en GitHub (#82)

---

## Relevant files
- `core_v2/systems/PlateContentStream.gd` — _refresh_active_slots(), _activate_slot(), _ready()
- `core_v2/tests/PlateContentPushBoxes.gd` — bug fix en _settle_pushables()
- `core_v2/player/PlayerControllerV2.gd` — visual_push_correction smoothing
- `core_v2/systems/PlateSlotConfig.gd` — NUEVO: clase de config para inspector
- `core_v2/components/PlateContentRoot.tscn` — puede necesitar PlateSlotConfig por defecto
- `core_v2/levels/BaseTerrace.tscn` — agregar PlateSlotConfig hijos

## Decisions
- PlateSlotConfig extends Node (no Spatial) — sin representación visual, solo datos
- Sticky slot: preservar key→slot binding mientras el key sea candidato activo
- visual_push_correction lerp en PlayerControllerV2, NO en el animator
- Scope excluido: no reimplementar _apply_push_constraint() completo, solo suavizar corrección visual
