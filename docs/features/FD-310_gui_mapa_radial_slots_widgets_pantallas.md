# FD-310: Mapa de la GUI de OdiseaOS — radial, slots, widgets y pantallas

**Status:** Design
**Priority:** P1
**Effort:** Large
**Created:** 2026-09-20
**Completed:** -
**Parent:** FD-296 (OdiseaOS) · FD-304 (interfaz diégetica con gamepad)
**Relacionadas:** FD-295 · FD-297 · FD-298 · FD-305 · FD-306 · FD-307 · FD-309

## Propósito

Este FD **no propone features nuevas**: es el **mapa autoritativo de la GUI actual**.
Existe porque la arquitectura de la GUI está repartida en 10 FDs, varios con drift
entre sí (ver §7), y hoy no hay un solo documento que responda "¿qué piezas tiene la
GUI, cómo se hablan y cuál es el contrato de cada una?".

Los FDs de feature siguen siendo dueños de su pedazo (radial → FD-306, drawer →
FD-305, gamepad → FD-304). Este doc es el **plano de conjunto** al que esos FDs se
refieren. Todo lo afirmado aquí fue verificado contra el código el 2026-09-20
(commit base de la rama de trabajo `feature/FD-309-interactable-hudable-placeholder`);
cada bloque trae la ruta del archivo.

**Regla de mantenimiento:** si el código cambia de forma que invalida una sección de
este doc, se actualiza este doc en el mismo PR. Un mapa desactualizado es peor que
ninguno.

---

## 1. Modelo conceptual: 4 piezas, 3 capas

La GUI de OdiseaOS se entiende con **4 piezas** y **3 capas**. Cualquier confusión en
el proyecto sale de mezclarlas.

### Las 4 piezas

| Pieza | Qué es | Dueño del contrato |
|---|---|---|
| **Pantalla** (*screen*) | Una unidad de contenido hudable: linterna, multi-tool, Cargol, domo, criocápsula. Tiene id estable, título, snapshot y acciones. | `HUDableComponent` (el prop) |
| **Widget** | La representación **2D pequeña** de una pantalla dentro de un slot (barra de batería, filas de estado). | `<Screen>Widget.gd/.tscn` |
| **Slot** | Uno de los **4 casilleros** donde el jugador guarda pantallas. Geometría fija, teclas 1–4. | `HudSlots.gd` |
| **Radial** | El menú circular que aparece en modo HUD para elegir entre las pantallas registradas. | `RadialSelectorV2.gd` |

La relación es: el **radial** elige una **pantalla**; la pantalla se fija a un
**slot** (o se abre directo); el slot muestra el **widget** de esa pantalla.

### Las 3 capas de interacción (FD-304 §2)

| Capa | Cómo se entra | Qué hacen los hombros/tab | Estado del mundo |
|---|---|---|---|
| **Juego** | por defecto | acciones de gameplay | corre |
| **HUD** | TAB (teclado) / Y (gamepad) | slots 1–4 | **pausado** sin menú (`PauseManager.pause_hud_mode`) |
| **Pantalla** | abrir una pantalla desde el HUD | funciones del widget (`hud_gamepad_actions()`) | según origen |

---

## 2. Estado actual verificado (código)

Inventario real, con líneas y rutas. Total del paquete `core_v2/ui/`: **~10.400 líneas
de GDScript**.

### 2.1 Núcleo (autoloads y componentes)

| Archivo | Líneas | Responsabilidad |
|---|---|---|
| `core_v2/autoloads/SuitOS.gd` | 391 | Registro de pantallas, 4 slots, canal de acciones, hápticos, persistencia (`replay_sync`). Fuente de verdad. |
| `core_v2/autoloads/SuitOSContextDriver.gd` | 32 | Alimenta el contexto (posición del jugador + `focus_id`) a 10 Hz. |
| `core_v2/components/HUDableComponent.gd` | 110 | Componente que declara una pantalla; se auto-registra al entrar al árbol. |
| `core_v2/autoloads/PauseManager.gd` | 242 | Dueño exclusivo de `get_tree().paused`, incluido el modo HUD. |

### 2.2 Capa HUD y widgets (`core_v2/ui/hud/`, 3.410 líneas)

| Archivo | Líneas | Rol |
|---|---|---|
| `HudModeOverlay.gd` | 910 | Overlay del modo HUD: radial, selección, drag a slot, montaje de la vista. |
| `SuitOSWidgetHost.gd` | 709 | Monta/actualiza/recicla los widgets de los 4 slots (hold 400 ms/12 px, swipe-out 48 px, reciclaje). |
| `RemoteHudBackend.gd` | 354 | Réplica del HUD para el teléfono; emite las **mismas señales** que `SuitOS`. |
| `HudViewMount.gd` | 263 | Presentador diegético (3D) + capa 2D; shader `HoloScreen2D`. |
| `HoloTerminalWidget.gd` | 106 | Widget de terminal holográfica (resumen de criogenia). |
| `ZoomRuler.gd` | 96 | Regla de zoom del control remoto. |
| `FlashlightWidget.gd` | 86 | Widget linterna: barra de batería + toggle. |
| `HudWidgetAction.gd` | 79 | Despacho de acción del widget → backend remoto o `SuitOS.perform_action`. |
| `SystemStatusWidget.gd` | 67 | Widget de estado del domo (reactor/O2/presión/temperatura). |
| `CargolWidget.gd` | 65 | Widget del dron Cargol. |
| `HudSlots.gd` | 60 | Geometría y reglas compartidas de los 4 slots. |
| `HudTabGesture.gd` | 56 | Tap vs hold de TAB/teclas de slot (`HOLD_TICKS = 24`). |
| `MultiToolWidget.gd` | 44 | Widget del multi-tool. |

**Radial:** `core_v2/ui/radial/RadialSelectorV2.gd` sobre el addon `addons/radial_menu`.
Hit-testing y aguja son custom porque la matemática de índices del addon tiene un
off-by-one con 3 opciones (ver FD-306).

### 2.3 Proveedores de pantalla hoy (`core_v2/things/`)

Todos `extends HUDableComponent`. **No hay un solo `.tscn` que instancie un
`HUDableComponent`**: el wiring vive en `_enter_tree`/código.

| Pantalla | `hud_screen_id` | Título | Acciones |
|---|---|---|---|
| `FlashlightScreen.gd` | `player:flashlight` | Linterna | `["toggle"]` |
| `MultiToolScreen.gd` | `player:multitool` | Multi-tool | — |
| `CargolScreen.gd` | `drone:cargol` | Cargol | — |
| `SystemStatusScreen.gd` | `ship:systems` | Domo | — |

La única asignación por defecto es `DEFAULT_PINS = ["player:flashlight","","",""]` en
`SuitOS.gd:43` (y duplicada en `RemoteHudBackend.gd`).

### 2.4 Capa retro OdiseaOS (`core_v2/ui/retro/`) — **UI paralela**

| Archivo | Líneas | Rol | Estado |
|---|---|---|---|
| `OYS_Console.gd` | 1.262 | Consola: comandos, cvars, alias, VFS, pipelines, cfg. | funcional (debug) |
| `DebugOverlay.gd` | 419 | Desktop retro: ventanas, taskbar, foco. | debug |
| `SubtitlesOverlay.gd` | 322 | Subtítulos/hints en pantalla. | **release** |
| `OYSShell.gd` | 319 | Vista de terminal (render de logs, autocompletado, historial). | funcional |
| `OysCameras.gd` | 248 | Switcher de cámaras con datos reales. | funcional |
| `RetroWindow.gd` | 154 | Ventana flotante (drag/foco/maximize/close). | funcional |
| `OysCalc.gd` / `NodeScan.gd` / `OysStatus.gd` / `OysTransit.gd` / `app_registry.gd` | 146/107/71/74/33 | apps del desktop. | demo / debug / **huérfana** |

**Conclusión importante:** la capa retro **no es la GUI de OdiseaOS**. Son dos UIs
paralelas que solo comparten la familia tipográfica SixtyFour para títulos; las
paletas son distintas (retro verde `#9bfa94` / ámbar vs. HUD cyan). Ver §7-10.

### 2.5 Menús, pantallas y overlays

| Archivo | Líneas | Rol | Cuándo |
|---|---|---|---|
| `Menu.gd` | 359 | Menú principal (+ boot de UpdateManager y consent). | arranque |
| `OptionsMenu.gd` | 342 | Opciones (idioma, audio, render, telemetría, low-end). | embebido en Menu y PauseMenu |
| `PauseMenu.gd` | 111 | Pausa; `set_minimal(true)` al perder foco. | CanvasLayer 50 |
| `RemoteControlHome.gd` | 472 | Cliente remoto; monta el **mismo** `SuitOSWidgetHost` con `RemoteHudBackend`. | tras emparejar |
| `RemoteControlMenu.gd` | 231 | Descubrimiento/emparejamiento LAN. | bajo demanda |
| `FirstRunConsent.gd` | 163 | Consentimiento de telemetría. | primera ejecución |
| `overlay/InfoOverlay.gd` | 106 | Panel de info de zona (pausa el árbol). | al mirar info |
| `overlay/ScreenEffectsOverlay.gd` | 172 | Viñeta de muerte + barras cinemáticas. | muerte |
| `overlay/HeatVignette.gd` | 151 | Viñeta roja de calor (visual pura). | gestión térmica |
| `overlays/ProtocolOverlay.gd` | 52 | Franja de "protocolo". | protocolos |

### 2.6 Capas de dibujo (orden real de solapamiento)

| Capa | Dueño | Contenido |
|---|---|---|
| 200 | `VirtualMouse` | cursor de gamepad |
| 115 | `OverlayUIManager` | slots `Passive` / `HUD` / `Modal` (aquí vive `HudModeOverlay`) |
| 100 | `MobileUIManager` | joystick, botones táctiles, cámara táctil |
| 50 | `PauseMenu` | pausa y opciones |
| — | `SuitOS` / `SuitOSWidgetHost` / `OYS_Console` bajo `/root` | lógica y widgets de slot, **fuera** del árbol de escena |
| diegético 3D | `HudViewMount` | vistas de pantalla en el mundo (shader `HoloScreen2D`) |

El orden táctil vs. pausa vs. widgets está documentado en `MobileUIManager.gd:238-239`
y es el origen de varios bugs de toque.

---

## 3. Flujo de datos end-to-end

Ruta completa, con nombres reales de señales:

```
[1] INPUT
    teclado (TAB, teclas 1-4) + gamepad (Y, hombros)
      → InputProviderV2._read_live_input()   →  InputDataV2.hud_mode / .hud_slot
      (los campos viajan en el STREAM grabado: el tap/hold se decide contando
       24 ticks del replay, NO con Input.is_action_pressed en vivo → replay OK)

[2] GESTO
    HudTabGesture (HOLD_TICKS=24)  →  TAP / HOLD / HOLD_RELEASE
      → HudModeOverlay._physics_process() decide transición

[3] REGISTRO
    cada prop con HUDableComponent  →  SuitOS.register_screen(screen)
      id = screen_id() → hud_screen_id → get_name()
      señales: screen_registered / screen_unregistered
      contexto: SuitOSContextDriver → 10 Hz → SuitOS.set_context(pos, focus_id)

[4] SELECCIÓN (modo HUD)
    SuitOS.open_hud_mode() → OverlayUIManager.ensure_overlay(SLOT_MODAL)
      → PauseManager.pause_hud_mode()   (mundo pausado, SIN PauseMenu)
      → HudModeOverlay lee SuitOS.get_registered_screens()
      → RadialSelectorV2.point_at(center + aim)   (vector acumulado, AIM_RADIUS 120)
      → option_selected(idx) → HudModeOverlay._select(idx)
          si _target_slot >= 0: SuitOS.pin_to_slot(id, slot)
          luego: SuitOS.open_screen(id)

[5] SLOTS
    SuitOS._pinned[4]  → reevaluate_slots()  → snapshot por slot
      señal: widget_changed(slot, snapshot)   (solo si cambia el hash)
      → SuitOSWidgetHost._on_widget_changed()
          snapshot vacío → placeholder
          mismo screen_id y tipo → update_snapshot / set_snapshot in place
          distinto → instancia screen.widget_scene() y _place()

[6] VISTA
    SuitOSWidgetHost decide presentación según el tipo de pantalla:
      widget 2D  → PanelContainer en el slot
      vista 3D   → HudViewMount → HudViewPresenter.tscn + shader HoloScreen2D
      view_2d    → para el control remoto
    Transición de entrada/salida según view_transition_origin():
      HoloTerminal → cámara de foco (FocusedRig) | sistema → 1ª persona | remoto → fundido 2D
    (FD-297; ~0.35–0.45 s, corre en pausa)

[7] ACCIÓN
    tap del widget → HudWidgetAction.perform()
      → ancestro con perform_hud_widget_action() (control remoto)
      → o SuitOS.perform_action(screen_id, op, args)
          valida has_screen(id) y op ∈ allowed_actions()
          delega en el perform_action de la pantalla
      → la pantalla muta su estado → state_changed
          → SuitOS reevalúa → widget_changed (vuelve a [5])
      → SuitOS.trigger_haptic(kind) → Haptics.gd (mando / teléfono)
```

**Persistencia:** `SuitOS` está en el grupo `replay_sync` (`get_snapshot`/
`restore_snapshot`). `CheckpointManager.capture_replay_sync_state()` +
`TeleportSystem` lo guardan dentro de `CheckpointResource.slots["last"]`. Al restaurar
se re-resuelve por `screen_id`; si la fuente ya no existe, el slot muestra el último
snapshot con `"source":"offline"`.

**Control remoto:** el teléfono corre el mismo binario, monta el mismo
`SuitOSWidgetHost` pero con `RemoteHudBackend` como backend. Las **pantallas viajan
como snapshots JSON-safe**, nunca como nodos ni video. `hud_mode` **no** viaja: el modo
HUD es local al dispositivo.

---

## 4. Contratos (lo que hay que respetar al tocar la GUI)

### 4.1 `SuitOS` (autoload) — API pública real

```gdscript
# señales
screen_registered(screen) / screen_unregistered(screen)
screen_opened(screen) / screen_closed(screen)
widget_changed(slot: int, snapshot: Dictionary)
hud_mode_changed(active: bool)
haptic(kind, intensity, duration)

# registro
register_screen(screen) -> void        # idempotente
unregister_screen(screen) -> void
has_screen(id) -> bool ; get_screen(id) ; get_registered_screens()

# modo HUD
open_hud_mode(by_slot: bool, screen_id: String, slot: int) -> void
close_hud_mode() -> void

# slots
pin_to_slot(id, slot) ; move_slot(from, to) ; clear_slot(slot)
get_pinned_slots() ; slot_screen_id(slot) ; get_slot_snapshot(slot)
reevaluate_slots() -> void

# acciones y hápticos
perform_action(screen_id, op, args := {}) -> Dictionary   # {"ok":bool, "error":String}
trigger_haptic(kind, intensity := -1.0, duration := -1.0)
save_state() / restore_state() ; get_snapshot() / restore_snapshot()
```

### 4.2 `HUDableComponent` — lo que declara una pantalla

- `hud_screen_id` (estable entre saves), `hud_screen_title`, `hud_screen_icon`
- `hud_view_scene`, `hud_widget_scene`
- `default_relevance`, `allowed_actions_list`
- Señal `state_changed`
- Métodos virtuales: `screen_id()`, `screen_title()`, `screen_icon()`,
  `view_scene()`, `widget_scene()`, `view_transition_origin()`,
  `relevance(context) -> float 0..1` (**pura**), `allowed_actions()`,
  `perform_action(op, args)`, `widget_snapshot()`

**Reglas duras del contrato:**

1. Todo lo que viaja a slots, HUD y remoto es **data pura serializable**
   (`widget_snapshot()` → JSON-safe, `"proto":1`, **completo e idempotente**, sin
   deltas en v1). Nunca nodos, `NodePath` ni texturas.
2. `relevance()` es pura y **no asigna slots**: nada se autoasigna (decisión
   explícita del rediseño 2026-09-13). Solo ordena el radial.
3. OdiseaOS **no crea** un segundo sistema de presentación, pausa ni transporte:
   presenta vía `OverlayUIManager` + `TerminalHUDBridge`, pausa vía `PauseManager`,
   corte por escena vía el patrón de `DebugConsoleManager`, transporte vía
   `RemoteControlServer.send_ui_directive`.

### 4.3 Bindings reales (`project.godot`, líneas 3133–3158)

| Acción | Tecla | Gamepad |
|---|---|---|
| `hud_mode` | `scancode 16777218` (TAB) | `button_index 3` |
| `hud_slot_1..4` | `physical_scancode 49..52` (teclas "1"–"4") | — |

deadzone 0.5 cada una. `InputProviderV2._read_live_input` toma **la primera** `hud_slot_%d`
sostenida (`hud_slot = 0` = ninguna).

---

## 5. Cómo se agrega una pantalla nueva (receta)

1. Escribir `<Nombre>Screen.gd` que `extends HUDableComponent` con
   `hud_screen_id` estable, `hud_screen_title`, `widget_snapshot()` puro y
   `allowed_actions_list` + `perform_action()` si tiene acciones.
2. Escribir `<Nombre>Widget.tscn` (PanelContainer) que consuma el snapshot en
   `update_snapshot()` / `set_snapshot()`.
3. Colgar el componente del prop (patrón análogo a `marker_config` de
   `InteractableEntity`) o, si es una pantalla del jugador, registrarla en código.
4. **No** tocar `SuitOS`, `HudModeOverlay` ni `SuitOSWidgetHost`: el registro es
   automático al entrar al árbol.
5. Si necesita vista propia (3D o 2D), agregar `view_scene()` y
   `view_transition_origin()`.

> Nota: el paso 1–2 es hoy **manual y repetitivo**. Ver FD-311 (faltantes) y el
> review de refactor (`docs/engineering/gui-refactor-review.md`): una clase base
> `HudWidget` eliminaría ~4 widgets casi idénticos.

---

## 6. Las 4 piezas, una por una (intención de diseño)

### 6.1 Pantallas
Una pantalla es una **unidad de contenido con identidad estable**. El id sobrevive
saves, cambios de escena y el viaje al teléfono. Si el id cambia, se rompe la
persistencia de slots y el estado del remoto. **El id es un contrato de guardado.**

### 6.2 Slots
4 casilleros, numerados 1–4 en la UI: 1–2 a la izquierda, 3–4 a la derecha
(`HudSlots.gd`: `COUNT=4`, `SLOT_ROW_HEIGHT=96`, `SLOT_GAP=8`, `SLOT_PADDING=16`).
**Solo el jugador los llena** (tecla, radial o arrastre). Un slot vacío es un
contorno inerte, no un error. `pin_to` garantiza que una pantalla nunca ocupe dos
slots. El slot 1 arranca con la linterna.

### 6.3 Widgets
El widget es la **cara chica** de una pantalla: lo que se ve en el slot sin abrirla.
Su única obligación es renderizar un snapshot. Los que existen (`FlashlightWidget`,
`SystemStatusWidget`, `CargolWidget`, `MultiToolWidget`, `HoloTerminalWidget`) son
casi idénticos en estructura y **no comparten base**.

### 6.4 Radial
Aparece **solo** en modo HUD y **solo si hay ≥2 pantallas** registradas
(`_open_radial` con ≤1 no lo abre). Se apunta con vector acumulado (stick, mouse,
touch o joystick táctil), `dead_zone` lleva al hub central ("...", FD-306), confirmar
con `ui_accept`/gatillo, salir con `ui_cancel`/TAB. Presenta **solo favoritos** (máx 6,
FD-305/306); el drawer lista el resto.

---

## 7. Drift y contradicciones conocidas (documentadas, no resueltas)

Estas son discrepancias entre FDs que **este mapa deja visibles a propósito**. Cada
una necesita una decisión; ninguna es un bug de código.

| # | Drift | FDs | Gravedad |
|---|---|---|---|
| 1 | **Modelo de slots:** "Slot A automático (relevance) + Slot B fijado" vs. "4 slots que solo llena el jugador". El texto viejo sigue citándose en F4/FD-307/FD-309. | FD-296 §Contratos vs. §5 / FD-305 / FD-306 | Alta (confunde a quien lee el FD como spec) |
| 2 | **4 slots en el teléfono:** §6/F4 dice que el teléfono monta los 4 slots; §"Fuera de alcance" dice que sigue con A/B. | FD-296 consigo misma | Media |
| 3 | **El radial fija o no:** §4-3a "abre sin fijar", §F3 "confirmar fija pin en Slot B". FD-305/306 resuelven del lado nuevo. | FD-296 consigo misma | Media |
| 4 | **Zona muerta del centro:** red de seguridad (FD-296/304) vs. item hub "..." que la invierte (FD-305/306). | FD-296 → FD-305/306 | Baja (cambio aceptado, no documentado) |
| 5 | **Entrada al modo HUD:** TAB tap/hold (FD-296) vs. **Y** sticky (FD-304). FD-304 reemplaza el gesto sin marcar herencia. | FD-296 vs. FD-304 | Media |
| 6 | **Status vs. índice:** FD-297/298 dicen `Design` en el header, el `FEATURE_INDEX` los lista como `Implemented`. | bookkeeping | Baja |
| 7 | **Roster de criocápsulas:** FD-304 §10, FD-307 y FD-309 tocan el mismo roster; la referencia cruzada pedida por FD-307 no está anotada. | FD-304 / FD-307 / FD-309 | Media |
| 8 | **Persistencia de favoritos:** FD-305 describe un `save_state()` que solo guarda `pinned_slots`; FD-296 describe además `_last_snapshots_cache`/`last_snapshots`. | FD-305 vs. FD-296 | Baja |
| 9 | **`hud_screen_icon` muerto:** declarado desde FD-296, "no se usa en una sola línea del juego" (FD-306 §3); FD-309 asume que ya entra al drawer. | FD-296 / FD-306 / FD-309 | Media |
| 10 | **Dos UIs paralelas:** la capa retro OYS (holoterminales verde/ámbar, desktop debug) y el HUD de OdiseaOS (cyan, slots) comparten solo la fuente. Ningún FD dice qué pasa con la retro en el producto final. | sin dueño | **Alta (decisión de producto)** |

---

## 8. Out of Scope

- Implementar cualquiera de los faltantes listados en **FD-311** — este doc solo mapea.
- Rediseñar el radial (es FD-306), el drawer (FD-305) o el gamepad (FD-304).
- Definir el destino de la capa retro OYS (drift #10): requiere decisión de Sebastian.
- i18n de la GUI (es FD-303 / FD-308).

## 9. Open Questions

1. ¿Se declara oficialmente "4 slots manuales, sin autoasignación" y se **corrigen los
   textos viejos** de FD-296 F4/FD-307/FD-309 (drift #1), o se revive el modelo A/B?
2. ¿La capa retro OYS se mantiene como herramienta de debug interna, se promueve a
   diegético del juego, o se retira (drift #10)?
3. ¿Este FD-310 reemplaza a FD-304 como documento de referencia del "mapa HUD", o
   FD-304 queda como el FD del *gamepad* exclusivamente?
