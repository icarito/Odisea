# Review de código — GUI de OdiseaOS y propuesta de refactor

**Fecha:** 2026-09-20 · **Cifras re-medidas:** 2026-09-20 sobre `main` `be301b06`
**Alcance:** `core_v2/ui/` (13.218 líneas GDScript) + `core_v2/autoloads/SuitOS.gd`
**Base original:** rama `feature/FD-309-interactable-hudable-placeholder`
**Autor:** Odiseo (consultor)
**Docs hermanos:** `gui-map-2026-09-20.md` (mapa de la GUI), FD-312 (faltantes por urgencia)

> **Las cifras de la primera versión quedaron cortas en días.** Se midieron sobre una
> rama de trabajo mientras `main` crecía por debajo: daban `HudModeOverlay` 910 y
> `SuitOSWidgetHost` 709. Los números de este documento son los de `main`, y el
> diagnóstico **se agrava**, no se ablanda. Contexto: el paquete `core_v2/ui/hud/`
> **no existía antes del 2026-09-12** — son 5.204 líneas en 19 archivos y 34 commits
> en ocho días.

---

## 1. Veredicto en una línea

La GUI **funciona y su arquitectura de fondo es correcta** (SuitOS como único registro,
data pura serializable, modos explícitos). El problema no es el diseño, es que **dos
archivos concentran el 58% del código** (`HudModeOverlay` **2.041** + `SuitOSWidgetHost`
**1.009** = 3.050 de 5.204 en `ui/hud/`) y **duplican entre sí la misma máquina de
estados de arrastre**. `HudModeOverlay` tiene 109 funciones, un `_input()` de 235 líneas
y 24 banderas booleanas sin FSM; `AGENTS.md` §2.2 pide componentes de menos de 200
líneas, o sea lo excede 10×. El refactor rentable es **extraer esa máquina duplicada y los hold/drag
de cada archivo**, no reescribir el HUD.

---

## 2. Lo que está bien y NO hay que tocar

1. **`SuitOS` como único punto de registro y acción.** Ningún widget llama a otro widget.
   Todo pasa por señales. Es el patrón correcto y hay que defenderlo.
2. **Contrato de data pura.** `widget_snapshot()` JSON-safe es lo que permite que el
   mismo `SuitOSWidgetHost` corra en el teléfono. Cualquier refactor que meta nodos en
   los snapshots **rompe el control remoto**. Línea roja.
3. **`HudSlots.gd` como geometría compartida** entre host local y remoto. Ya está bien
   factorizado; hay que usarlo más, no menos.
4. **Separación presentación/pausa:** `PauseManager` es el dueño exclusivo de
   `get_tree().paused`. `SuitOS` no lo toca. Correcto.
5. **Reuso del presentador** por origen de transición (FD-297). Bien.

---

## 3. Hallazgos por severidad

### S1 — Duplicación de la máquina de arrastre/shock (el hallazgo importante)

`HudModeOverlay` y `SuitOSWidgetHost` implementan **casi la misma máquina** de forma
independiente:

| Concepto | `HudModeOverlay` | `SuitOSWidgetHost` |
|---|---|---|
| Umbral de hold | `DRAG_HOLD_MSEC = 400` (:36) | `HOLD_MSEC = 400` (:15) |
| Umbral de drag | `TOUCH_MIN_DRAG` (12 px) | `DRAG_START = 12.0` (:21) |
| Posición/reloj de press | `_touch_start` / `_touch_press_msec` | `_press_position` / `_press_msec` |
| Flags de arrastre | `_drag_ghost` / `_drag_option` / `_dragging_view` | `_dragging` / `_drag_origin` |
| Hit-test de widget | `_touch_on_widget` | `_widget_hit` |
| Lógica drop→slot | `_drop_option` / `_drive_option_drag` / `_drive_view_drag` | `slot_at` / `_end_drag` / `show_drop_targets` |

Consecuencia real: los **umbrales se pueden desincronizar** (hoy coinciden por copia
manual, no por constante compartida) y una corrección en un lado no llega al otro.

### S2 — God methods y estado sin FSM

- `HudModeOverlay._input` (:319–455, ~136 líneas) despacha teclado, touch, mouse, drag
  y focus en un bloque.
- `HudModeOverlay._physics_process` (:183–231) mezcla gestos de TAB/slot, apuntado y
  widget.
- El estado del modo HUD vive en **~20 flags sueltos** (`_opened`, `_tab_hold_active`,
  `_target_slot`, `_drag_ghost`, `_dragging_view`, …) sin enum ni tabla de transiciones.
  Esto es la causa raíz de los bugs de "toque fantasma" entre capas.
- `OYS_Console.gd` (1.262 líneas) es un god object completo: comandos + cvars + alias +
  VFS + pipelines + autocompletado + persistencia + intérprete OYS. El **VFS solo**
  (:878–1261, ~380 líneas) merece clase propia.

### S3 — Acoplamientos implícitos que rompen al renombrar

- `SuitOSWidgetHost` se busca **por path de nodo** (`/root/SuitOS/SuitOSWidgetHost`) en
  `PauseManager.gd:240` y `ScreenEffectsManager.gd:138`.
- `HudModeOverlay._widget_host()` (:646) recorre `get_tree().get_nodes_in_group("hud_widget_host")`
  **en cada frame de arrastre** buscando el que tenga el backend correcto.
- `"OYS_Console"` como nombre singleton hardcodeado en OYSShell, DebugOverlay y **8
  archivos externos** (`AnnaInterface`, `HoloTerminalV2`, `SessionManager`, …).
- `HUDableComponent` llama al dueño por introspección de strings
  (`get_hud_relevance`, `perform_hud_action`, `get_hud_snapshot`).
- `Menu.gd`/`PauseMenu.gd` resuelven botones por `find_node("Quit")` → frágil ante renombres.

### S4 — Código muerto y hotfixes frágiles

- `HudModeOverlay._ignores_widget_taps()` (:622) compara `Engine.get_idle_frames()`
  **exactamente** con `_hud_state_frame`; cualquier frame extra rompe el filtrado.
  Es un hotfix, no una solución.
- ~~Rama muerta en `HudModeOverlay:451`~~ — **FALSO POSITIVO, verificado 2026-09-20.**
  El `elif event.is_action("ui_accept") and _widget_screen_showing(): pass` (hoy `:733`)
  **no es código muerto**: cae a propósito en el `set_input_as_handled()` del final para
  que la navegación por foco de la GUI no oprima el mismo botón dos veces en el mismo
  toque. Borrarlo lo mandaría al `else: return` y cambiaría el comportamiento. Lo mismo
  el `pass` de `_on_drawer_favorited` (`:1156`), que es un no-op documentado.
- ~~`_cmd_calc`/`_cmd_nodescan` fallan siempre~~ — **cierto, y ya está arreglado**
  (2026-09-20): llamaban a `_open_calc`/`_open_nodescan`, que no existen; ahora usan
  `_open_app("CALC")`/`_open_app("NODESCAN")` del `AppRegistry`.
- ~~`OysTransit` huérfana~~ — **estaba completa y funcional**, solo faltaba registrarla.
  Con la capa de a bordo promovida a diegética, se registró como `TRANSIT` en vez de
  borrarla. `TouchButton.gd` ya no existe en el árbol.
- `HudViewMount`/`HudModeOverlay` no exponen señales propias: el host no puede saber si
  la GUI consumió un toque sin volver a picar el grupo.

### S5 — Comentarios de riesgo aceptado

- `# ponytail:` al final de `SuitOSWidgetHost.gd` (hoy ≈`:1007`) reconoce que **el hold del host se mide con
  reloj real, no con el stream de input** → esa parte del modo HUD **no es replayable**
  (a diferencia de TAB, que sí cuenta ticks). Es deuda de determinismo, no cosmética.

### S6 — Performance sin medir

- `SuitOS.reevaluate_slots()` (:272) reconstruye los snapshots de los 4 slots en **cada
  `set_context`** (que `SuitOSContextDriver` emite a 10 Hz). El guard por `hash()` corta
  las señales, no el cómputo.
- `_widget_host()` recorre el grupo por frame de arrastre (ver S3).
- `OYSShell._append_line` re-renderiza **todo** al pasar 5.000 líneas → O(n²) en sesiones
  largas de consola.

---

## 4. Propuesta de refactor (por fases, con criterio de parada)

> Principio: **no reescribir nada que ya esté en contrato**. Se extrae lo duplicado y se
> encapsula el estado. Cada fase es mergeable sola y no cambia comportamiento observable.

### Fase 1 — Extraer la máquina de gesto/arrastre (1–2 días)

**Objetivo:** una sola fuente de verdad para hold/drag/drop.

- Nuevo `core_v2/ui/hud/HudDragMachine.gd` (RefCounted o Node liviano) con:
  - constantes `HOLD_MSEC = 400`, `DRAG_MIN_PX = 12`, `SWIPE_MIN = 48`, `SWIPE_EXIT_*`;
  - estado `{press_pos, press_msec, dragging, drag_origin}`;
  - API: `begin(pos, msec)`, `update(pos, msec) -> {phase}`, `drop(pos, targets) -> {action, slot}`,
    `set_input_frame(frame)` (para el filtrado de toques).
- `HudModeOverlay` y `SuitOSWidgetHost` **consumen** la máquina; borran sus constantes y flags.
- Reemplazar `_ignores_widget_taps()` por la máquina comparando `input_frame` (no
  `Engine.get_idle_frames()`).
- Reemplazar `_widget_host()` por una referencia cacheada que se resuelva **una vez** en
  `_ready` (y se revalide con una señal de `SuitOS`, no por grupo).

**Criterio de aceptación:** los 400/12/48 existen en **un solo archivo**; drag y swipe se
comportan igual; `HudModeOverlay` baja ~150 líneas.

### Fase 2 — FSM explícita del modo HUD (1 día)

- Enum `HudState { CLOSED, RADIAL, SCREEN }` + sub-estado de gesto, con una tabla de
  transición `(state, input) -> state`.
- `HudModeOverlay._input` se parte en handlers por estado (`_on_input_radial`,
  `_on_input_screen`) en vez de un bloque de 136 líneas.
- Los ~20 flags quedan derivados del estado, no sueltos.

**Criterio:** los bugs de "toque fantasma" se vuelven reproducibles por estado, no por
timing de frame.

### Fase 3 — Base común de widgets (medio día)

- `core_v2/ui/hud/HudWidget.gd` (extends PanelContainer) con:
  - `set_snapshot(snapshot)` / `update_snapshot(snapshot)` genéricos;
  - helper `_on_state_changed(state_key, value)` para el patrón de re-layout;
- Los 5 widgets (`Flashlight`, `SystemStatus`, `Cargol`, `MultiTool`, `HoloTerminal`)
  pasan a `extends HudWidget` y borran el boilerplate duplicado.
- **No** toca el contrato de `widget_snapshot()` (la data sigue igual) → el control
  remoto no se afecta.

**Criterio:** un widget nuevo se escribe en ≤30 líneas de lógica propia.

### Fase 4 — Contrato de acciones tipado (1 día)

- `const HUD_OPS := { "toggle": ..., }` central (o enum + validador) en vez de
  `Array[String]` libre.
- `perform_action` devuelve un resultado tipado (`{ok, error_code, error_msg}`) con
  códigos enumerados; las pantallas declaran ops de un catálogo.

**Criterio:** el remoto puede validar una op **antes** de enviarla.

### Fase 5 (opcional) — Sacar el VFS de `OYS_Console` y limpiar muertos

- `OYS_Vfs.gd` con lo de `OYS_Console.gd:878–1261`.
- ~~Borrar `_cmd_calc`/`_cmd_nodescan`, `OysTransit`, `TouchButton.gd`~~ — **hecho el
  2026-09-20, pero al revés de como decía acá:** los comandos se implementaron y
  `OysTransit` se registró. Ver S4. Verificar antes de borrar: de los cuatro "muertos"
  de este review, uno era funcional, dos eran arreglables y el cuarto ya no existía.
- **Esta fase es separable** y de menor prioridad: es deuda de debug, no de gameplay.

---

## 5. Lo que NO haría (y por qué)

| Tentación | Por qué no |
|---|---|
| Reescribir `HudModeOverlay` desde cero | Perderías las decisiones finas (apuntado acumulado, transiciones por origen, filtro táctil de 4 capas) que costaron bugs. Extraer > reescribir. |
| Meter nodos/texturas en los snapshots para "simplificar" | Rompe el control remoto (data pura). Línea roja. |
| Migrar todo a `.tscn` de una | Hoy el wiring en `_enter_tree` funciona y es idempotente; migrar es churn sin beneficio inmediato. Documentar el patrón (mapa §5) y migrar pantalla por pantalla si molesta. |
| ~~Unificar el HUD con la capa retro~~ | **Superado por decisión de producto (2026-09-20):** la capa de a bordo se promueve a diegética. No se *unifican*: se declaran como dos superficies de un mismo sistema, cian = traje y verde/ámbar = nave. Lo que sí entra al refactor es pasar `RetroOS.tres` a tokens compartidos. |
| Optimizar `reevaluate_slots()` antes de medir | A 10 Hz con 4 slots puede ser irrelevante. Medir en el objetivo low-end; si duele, cachear por `screen_id` en vez de reconstruir. |

---

## 6. Orden recomendado y esfuerzo

| Fase | Qué | Riesgo | Esfuerzo | Desbloquea |
|---|---|---|---|---|
| 1 | `HudDragMachine` (hold/drag/drop unificado) | Bajo-medio | 1–2 d | Bugs de toque; menos líneas |
| 2 | FSM del modo HUD | Medio | 1 d | Bugs de "toque fantasma" |
| 3 | `HudWidget` base | Bajo | 0,5 d | Widgets nuevos baratos (P0-1) |
| 4 | Catálogo de ops tipado | Medio | 1 d | Control remoto robusto |
| 5 | VFS fuera de OYS_Console + limpieza | Bajo | 1 d | Deuda de debug |

**Fases 1 y 3 son las de mejor relación beneficio/riesgo** y no dependen de ninguna
decisión de producto pendiente. Las fases 1–2 tocan el mismo par de archivos: conviene
hacerlas en la misma sesión de trabajo.

---

## 7. Cómo delegarlo (Jules)

**Prerrequisitos antes de delegar:**
1. CI de `main` estable (AGENTS.md) — el refactor toca archivos que los FDs vigentes
   están moviendo; sin base verde, el diff se contamina.
2. Resolver/registrar los drifts del mapa §7, al menos el #1 (modelo de slots), porque
   la Fase 2 toca la FSM que los implementa. Lo resuelve el Manual del Tripulante.
3. Sebastián aprueba el alcance (Fase 1 sola, o Fases 1+2).

**Sugerencia de partición en tareas Jules:**
- **Tarea A (Fase 1):** `HudDragMachine` + migración de los dos consumidores + tests de
  umbral (hold 400 ms, drag 12 px, swipe 48 px) con casos límite.
- **Tarea B (Fase 3):** `HudWidget` base + migración de 4 widgets + render de snapshot.
- **Tarea C (Fase 2):** FSM del modo HUD. **Depende de A**; delegar después.

Cada tarea: rama `refactor/hud-<fase>`, PR contra `feature/FD-*` de trabajo (no `main`
directo mientras el HUD siga en ramas de feature).
