# FD-310: Widget contextual de interactuables — del subtítulo al HUD

**Status:** Implemented (v1)
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-09-19
**Completed:** 2026-09-19

## Implementación (2026-09-19)

v1 genérica, sin arte por prop:

- `SuitOSWidgetHost`: `show_context(snapshot) -> bool` monta un widget de contexto
  (PanelContainer + título + acción, estilo de widget) en el **primer slot libre**;
  `clear_context()` lo saca. No es un pin (no entra en `get_pinned_slots()`), se
  reubica en `_relayout()` y `refresh_visibility()` lo oculta con el resto del HUD.
- `PlayerHintManager.show_interaction_hint(text, source)`: con un interactuable en
  rango y slot libre, muestra el **widget de contexto** y no dibuja el subtítulo;
  sin slot libre (o sin host), cae al `PlayerHintOverlay` de siempre. El texto se
  sigue emitiendo por `visible_hint_changed` para el control remoto.
- `PlayerControllerV2` pasa el `best_target`; título = `screen_title()` →
  `interaction_title` → nombre del nodo humanizado. `InteractableBaseV2` suma el
  export opcional `interaction_title`.
- Además: el `SuitOSWidgetHost` (autoload) se oculta en `Menu.tscn` y el menú
  limpia el modo HUD/widgets al entrar, para que no queden dibujados al volver de
  una partida.

Pendiente: validación visual (checkpoint HUMANO) y las Open Questions.

## Problem

Hoy, cuando el jugador apunta a un interactuable, la guía sale como un **texto tipo subtítulo** al
pie de la pantalla (`PlayerControllerV2` → `PlayerHintManager.show_interaction_hint()` →
`PlayerHintOverlay`). Ese lenguaje visual es el de los subtítulos/OYS y no el de OdiseaOS: el traje
ya comunica estado con **widgets** (los cuatro slots del `SuitOSWidgetHost`), y un interactuable
cercano es exactamente un dato contextual de la suit.

Se quiere que el aviso del interactuable en rango aparezca como un **widget temporal** en el HUD,
no como una línea de texto abajo.

## Solution

Convertir el prompt del *mejor interactuable en rango* en un widget genérico temporáneo:

1. **Widget genérico** (`InteractableContextWidget`): mismo lenguaje visual que los widgets de
   OdiseaOS (PanelContainer + título + acción). No requiere arte por prop.
   - **Título**: `screen_title()` si el interactuable expone el contrato HUDable; si no, un
     `interaction_title` exportado opcional (`InteractableBaseV2`); si no, el nombre del nodo
     humanizado; último recurso `tr("Interactuable")`.
   - **Acción**: el prompt que ya existe hoy (`get_interaction_prompt()` /
     `interaction_text` / `focus_text`), sin la tecla.
2. **Slot libre temporal**: el widget se monta en el **primer slot vacío** del
   `SuitOSWidgetHost` (los slots que el jugador no tiene fijados), y se libera al salir de rango.
   No se persiste ni entra en `SuitOS.get_pinned_slots()`.
3. **Fallback sin pérdida**: si no hay slot libre, o el HUD no está disponible, el aviso sigue
   mostrándose con el texto actual (`PlayerHintManager`). El jugador nunca se queda sin guía.
4. **El control remoto no se rompe**: `PlayerHintManager` sigue publicando el texto resuelto por
   `visible_hint_changed` para el bridge; solo deja de **dibujarlo localmente** cuando el widget
   contextual tomó el aviso.

### Relación con FD-034

FD-034 definió el hint como "label de estado del HUD" y terminó implementado como texto. Este FD
**solo cambia la presentación del hint de interacción**: los hints de estado, manuales/OYS y los
del control remoto siguen igual (ver *Fuera de scope*).

### Comportamiento

- Entrar en rango del interactuable → aparece el widget en un slot libre, con título + acción.
- Cambiar de interactuable → el widget se actualiza en el mismo slot (sin parpadeo ni stacking).
- Salir de rango → el widget desaparece y el slot vuelve a quedar libre.
- Modo HUD abierto, pantalla abierta, cinemática o pausa → el widget se oculta con el resto de
  los widgets (`SuitOSWidgetHost.refresh_visibility()`); no se duplica con el modo HUD.
- Sin slot libre → texto de fallback (`PlayerHintOverlay`, como hoy).

## Considered Options

- **Widget propio por interactuable** (`hud_widget_scene` por prop): más rico, pero exige arte y
  autoría en decenas de props. Descartado para v1 (elegido: genérico con datos actuales).
- **Flotar junto al objeto** (proyección 3D → pantalla): más inmersivo, pero suma proyección,
  oclusión y multi-objetivo. Descartado por costo/riesgo.
- **Lugar fijo del HUD** (cajón reservado): simple, pero agrega una zona nueva de HUD. Descartado
  frente a reutilizar la geometría de slots que ya existe.
- **Selected**: widget genérico en un slot libre temporal, con fallback al texto actual.

## Fuera de scope

- Hints de estado (`show_status_hint`), manuales/OYS (`show_manual_hint`) y remotos
  (`show_remote_hint`): siguen como texto.
- Arte/iconos por interactuable.
- Interactuar tocando el widget (v1 es solo informativo).
- Cambios en `project.godot` (no se agrega autoload) y en escenas de nivel.

## Files to Modify

- `core_v2/ui/hud/InteractableContextWidget.tscn` (new) — widget genérico (título + acción).
- `core_v2/ui/hud/InteractableContextWidget.gd` (new) — `update_snapshot()`/`set_snapshot()`.
- `core_v2/ui/hud/SuitOSWidgetHost.gd` (modify) — overlay temporal en slot libre, visibilidad y
  limpieza.
- `core_v2/ui/hud/HudSlots.gd` (modify si hace falta) — helper de slot libre.
- `core_v2/autoloads/PlayerHintManager.gd` (modify) — canal de contexto + supresión del dibujo
  local del hint de interacción.
- `core_v2/player/PlayerControllerV2.gd` (modify) — publicar/limpiar el interactuable en rango.
- `core_v2/components/InteractableBaseV2.gd` (modify) — `interaction_title` opcional.
- `core_v2/tests/test_interactable_context_widget.gd` (new).
- `core_v2/tests/test_player_hint_manager.gd` (modify) — el hint de interacción ya no dibuja si
  hay widget.
- `core_v2/tests/test_suitos_widget_host.gd` (modify) — slot libre temporal.

## Verification

1. En gameplay, apuntar a un interactuable sin slots ocupados: aparece el widget en un slot libre
   con título y acción; al mirar otro, se actualiza; al alejarse, desaparece.
2. Ocupar los 4 slots: el aviso cae al texto inferior (fallback) sin perderse.
3. Abrir HUD/drawer, pausa y cinemática: el widget se oculta y no se duplica.
4. En el control remoto, el host sigue mandando el texto del interactuable (`hint`).
5. Tests puntuales:
   ```shell
   ./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_suitos_widget_host_gd
   ./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_player_hint_manager_gd
   ./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_interactable_context_widget_gd
   ```
6. Captura visual del widget con `./test_prop.sh`/`./test_ui.sh` antes de cerrar la iteración.

## Inventario de assets (verificado 2026-09-19)

| Asset | Estado | Nota |
|---|---|---|
| `core_v2/autoloads/PlayerHintManager.gd` | EXISTE | Punto único del hint de interacción (`show_interaction_hint`, 30/34). |
| `core_v2/ui/overlay/PlayerHintOverlay.gd` / `.tscn` | EXISTE | Dibujo actual del texto al pie; queda como fallback. |
| `core_v2/player/PlayerControllerV2.gd` | EXISTE | `_process_interaction` (2029) elige `best_target`; `_show_interaction_prompt` (2007). |
| `core_v2/ui/hud/SuitOSWidgetHost.gd` / `.tscn` | EXISTE | 4 slots, `_place`, `refresh_visibility`, fallback Label. |
| `core_v2/ui/hud/HudSlots.gd` | EXISTE | `COUNT = 4`, `slot_key(i)`. |
| `core_v2/autoloads/SuitOS.gd` | EXISTE | `pin_to_slot`, `get_pinned_slots`, señal `widget_changed`. |
| `core_v2/components/HUDableComponent.gd` | EXISTE | `widget_scene()`, `screen_title()`, `widget_snapshot()`. |
| `core_v2/components/SuitOSRemoteBridge.gd` | EXISTE | Replica `visible_hint_changed` → directiva `hint` (36/41). |
| `core_v2/components/InteractableBaseV2.gd` | EXISTE | `interaction_text`, `focus_text`. |
| `core_v2/ui/hud/FlashlightWidget.tscn` | EXISTE | Referencia de estilo (PanelContainer 210×80). |
| `core_v2/ui/hud/InteractableContextWidget.tscn` / `.gd` | FALTA | Crear (genérico, sin icono en v1). |
| `core_v2/tests/test_suitos_widget_host.gd` | EXISTE | Base para los casos de slot libre. |
| `core_v2/tests/test_player_hint_manager.gd` | EXISTE | Base para la supresión local. |

Referenciadores: `interaction_text` en 20 archivos `.gd`; `PlayerHintManager` en 12;
`SuitOSWidgetHost` en 17. **No se tocan props**: el título es genérico (contrato opcional).

## Riesgos y contratos

- **Determinismo (AGENTS §5.3)**: es UI pura. El scan ya vive en `_physics_process`; publicar el
  contexto es un efecto de presentación, no alimenta el movimiento ni introduce `randf()`. Sin
  estado nuevo de `replay_sync`.
- **Control remoto**: el bridge depende de `visible_hint_changed`. Mitigación: `PlayerHintManager`
  sigue emitiendo el texto del interactuable aunque no lo dibuje localmente.
- **Slot ocupado**: nunca pisar un slot fijado. Si no queda libre, fallback al texto. No persistir
  el widget temporal en el guardado de favoritos/slots.
- **Modo HUD / pantalla / cinemática**: `refresh_visibility()` ya oculta los widgets; el contexto
  debe nacer oculto en esos estados y no reactivarse hasta volver a gameplay.
- **Archivos compartidos**: no tocar `project.godot` (sin autoload nuevo) ni escenas de nivel.
- **GLES2 / perf**: Controls, sin animación por tiempo ni partículas; no requiere
  `_wants_continuous_step()`. Costo de un Control extra, despreciable.

## Decisiones (2026-09-19)

1. **Alcance**: solo el hint de interacción pasa a widget. Estado, manuales/OYS y control remoto
   siguen como texto. — Sebastián.
2. **Identidad**: widget genérico con los datos actuales (`screen_title`/nombre del interactuable +
   `interaction_text`/prompt). Sin arte por prop en v1. — Sebastián.
3. **Ubicación**: slot libre temporal del `SuitOSWidgetHost`; si no hay libre, fallback al texto
   inferior. — Sebastián.

## Open Questions

- ¿El widget debería poder tocarse/clicarse para disparar la acción en táctil? Recomendado: no en
  v1 (el botón de acción sigue siendo el camino).
- ¿Se muestra solo la acción primaria o también "Enfocar" cuando el interactuable lo permite?
  Recomendado: el mismo prompt combinado que hoy.
- Título cuando el prop no tiene ninguno: ¿nombre del nodo humanizado o un genérico
  `tr("Interactuable")`? Recomendado: nombre humanizado, y `interaction_title` para lo que importe.

## Plan de ejecución

| # | Tarea | Ejecutor | Archivos | Aceptación | Depende de | Estado |
|---|---|---|---|---|---|---|
| 1 | Widget genérico: escena + script (`update_snapshot`) con estilo de widget OdiseaOS | LOCAL | `core_v2/ui/hud/InteractableContextWidget.tscn`, `.gd` | captura de `test_prop.sh`/`test_ui.sh` aprobada por Sebastián | — | pendiente |
| 2 | Slot temporal en el host: montar/limpiar en slot libre, sumarlo a `refresh_visibility`, sin persistir; helper de slot libre | JULES | `core_v2/ui/hud/SuitOSWidgetHost.gd`, `core_v2/ui/hud/HudSlots.gd`, `core_v2/tests/test_suitos_widget_host.gd` | test nuevo: aparece en slot libre, se actualiza sin parpadeo, se limpia al salir, no toca slots fijados | — | pendiente |
| 3 | Canal de contexto: publicar/limpiar desde el controller, `interaction_title` opcional, supresión del dibujo local, fallback al texto | JULES | `core_v2/autoloads/PlayerHintManager.gd`, `core_v2/player/PlayerControllerV2.gd`, `core_v2/components/InteractableBaseV2.gd`, `core_v2/tests/test_player_hint_manager.gd`, `core_v2/tests/test_interactable_context_widget.gd` | tests nuevos verdes; con widget activo no se dibuja texto; sin slot libre vuelve el texto; `visible_hint_changed` sigue emitiéndose | 2 | pendiente |
| 4 | Prueba en vivo: legibilidad, ubicación, no ensuciar el HUD, remoto | HUMANO | — | Sebastián valida jugando | 1, 3 | pendiente |

### Cortes de paralelismo

- Tarea 1 (visual) y tarea 2 (lógica) tienen archivos disjuntos y pueden ir en paralelo.
- Tarea 3 consume la API de la tarea 2 (`show_context_widget`/`clear_context_widget`), por eso
  depende de 2.
- Ninguna tarea toca `project.godot` ni `core_v2/levels/**`.

## Checkpoints en vivo

1. **Tras tareas 1 y 2**: el widget se ve (aunque todavía lo dispare un test) — Sebastián juzga
   estilo, tamaño y ubicación en el slot.
2. **Tras la tarea 3**: jugar con interactuables reales (terminal, signage, ascensor) y juzgar que
   no ensucia, que no parpadea al cambiar de objetivo y que el fallback con 4 slots ocupados se
   siente bien.
3. **Cierre**: control remoto mostrando el `hint` del host.
