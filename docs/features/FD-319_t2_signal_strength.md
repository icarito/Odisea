# FD-319 — Tarea 2 (slice): Señal por distancia (`signal_strength`)

**Slice de:** FD-319 (ejes del traje). **Solo esta tarea.** No tocar urgencia ni protocolo.

## Objetivo

El widget contextual (FD-310) hoy aparece/desaparece por *apuntar* (binario). Esta tarea le
agrega degradación por distancia a la fuente, con `signal_strength` (0..1) como **data en el
snapshot** (no animación libre).

## Contexto verificado

- El widget contextual **NO es `InteractableContextWidget`** (ese nombre solo existe en la doc vieja de FD-310). El real, ya mergeado (`11dd75f5`), es el slot `__context__` de `SuitOSWidgetHost.gd` (`CONTEXT_WIDGET_NAME = "SuitOS_Context"`, `CONTEXT_SLOT = "__context__"`), que monta `InteractableSlotWidget.gd` alimentado por `InteractableSlotScreen.gd`.
- `core_v2/ui/hud/SuitOSWidgetHost.gd` — `show_context(snapshot)`, slot `__context__`, `_context_widget`.
- `core_v2/ui/hud/InteractableSlotWidget.gd` — ficha (icono/nombre/descripción/verbo), `update_snapshot()`.
- `core_v2/ui/hud/InteractableSlotScreen.gd` — envoltorio del interactuable en el slot.
- `core_v2/components/HUDableComponent.gd` — expone `screen_id`, `relevance()`, `view_transition_origin()`.
- `core_v2/ui/hud/HudWidget.gd` — `set_snapshot(dict)`, `is_offline()` (Manual §7/§8).
- Determinismo (AGENTS §5.3): la señal es lectura, no estado libre.

## Cambios

1. **Slot `__context__`** (en `SuitOSWidgetHost` + `InteractableSlotWidget`/`InteractableSlotScreen`): degradación legible por distancia del slot de contexto:
   - en rango → sólido, 100 % interactuable;
   - frontera → fade-in suave;
   - lejano → flicker suave conforme decae la señal;
   - fuera de rango → estado visual nuevo `FUERA_DE_RANGO` (previo al offline), luego desaparece.
   - `FUERA_DE_RANGO` no reemplaza `is_offline()`; es un estado previo.
2. **`HUDableComponent.gd`**: el `screen_id` declara `signal_strength` (0..1) derivada de la
   distancia (u otro aspecto del contexto).
3. **Snapshot**: contrato `signal_strength` serializable (sin nodos vivos dentro del widget).
4. **Tests** deterministas.

## Fuera de alcance (estricto)

- Urgencia / `OdiseaOSTheme` (Task 3). **No tocar.**
- `ProtocolWidget` / `ProtocolScreen` (Task 4). **No tocar.**
- Grafo de progresión (Task 5). **No tocar.**
- ImPlot3D / mapa 3D (F2).

## Aceptación

1. Apuntar a un prop y alejarse → fade-in → flicker → `FUERA_DE_RANGO` → desaparece, sin salto seco.
2. Determinista: `signal_strength` sale del snapshot, no de `OS.get_ticks`/`rand`.
3. Tests: `./.venv/bin/pytest tests/test_odisea_runner.py -k "signal_strength"` verde.

## Reglas

- No tocar `project.godot` ni escenas de nivel.
- No duplicar `SystemStatusWidget`.
- Composición sobre herencia; tipado estático; cada componente < 200 líneas.
