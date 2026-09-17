# FD-301: Cache de SessionManager en PlayerControllerV2._input()

**Status:** Planned
**Priority:** Medium
**Effort:** Small
**Created:** 2026-09-17
**Completed:** -

## Problem

`PlayerControllerV2._input()` (core_v2/player/PlayerControllerV2.gd:2177) resuelve
`get_node_or_null("/root/SessionManager")` en CADA evento de input. Durante mouse-look
con el cursor capturado esto dispara cientos de veces por segundo, y cada llamada
recorre resolución de ruta de autoload. El propio repo documenta el patrón correcto
y su costo: el comentario de FD-290 en SessionManager.gd:1559 ("buscar el autoload
por path en CADA tick de fisica se paga en cada replay") y el cache `_pm_prof`
(SessionManager.gd:1565-1571). El equivalente per-tick de este archivo
(`_sm_cache`, ~línea 3204) ya está cacheado; `_input()` quedó afuera.

## Solution

Cache perezoso de una sola resolución, idéntico al patrón `_pm_prof` de
SessionManager.gd:1565-1571:

```gdscript
var _sm_input = null
var _sm_input_buscado := false
```

En `_input()`, reemplazar la llamada por:

```gdscript
if not _sm_input_buscado:
    _sm_input_buscado = true
    _sm_input = get_node_or_null("/root/SessionManager")
var sm = _sm_input
```

El resto de la lógica (`sm and sm.player == self and sm.is_recording`) no cambia.

### Considered Options

- **Option A**: resolver en `_ready()` — riesgo: orden de ready entre autoload y
  escena si `_input` llega temprano; innecesario.
- **Option B**: cache perezoso con flag, patrón `_pm_prof` — resuelve en el primer
  evento real (autoloads garantizadamente listos), cero riesgo. **Selected.**
- **Option C**: cachear también los lookups de SessionManager en rutas de perf
  (líneas 2113/2684) — corren una vez por replay bajo `_replay_perf_on`; no hay
  ganancia. Fuera de alcance.

## Files to Modify

- `core_v2/player/PlayerControllerV2.gd` (modify: solo `_input()` y las dos vars nuevas)

## Constraints

- Godot 3 / GDScript 1.x, static typing donde el archivo ya la use.
- Cero cambio de comportamiento: es solo eliminar la resolución de ruta repetida.
- Los replays `.oys` existentes deben seguir pasando la CI determinista sin
  re-grabarse (no se toca captura ni lógica de input, solo el lookup del nodo).
- No tocar otros lookups del archivo ni de SessionManager.

## Verification

1. `grep -n 'get_node_or_null("/root/SessionManager")' core_v2/player/PlayerControllerV2.gd`
   muestra la llamada solo dentro del bloque de inicialización perezosa.
2. CI verde, incluido `determinism_tests.yml` (replays bit-a-bit idénticos).
3. Smoke manual: grabar 5 s con `is_recording` y verificar que el flag
   `session_recording` sigue activándose (el cache devuelve el autoload).
