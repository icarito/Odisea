# FD-304: Interfaz diégetica de OdiseaOS con gamepad (slots, modo pantalla, acordes, drag y radial)

**Status:** Implemented
**Priority:** P1
**Effort:** Large
**Created:** 2026-09-18
**Completed:** 2026-09-19
**Parent:** FD-296 (OdiseaOS) · FD-296 F3 (HudModeOverlay) · FD-296 F1.5 (SuitOSWidgetHost) · FD-298 (linterna) · FD-294 (control remoto)

## Problem

OdiseaOS (FD-296) ya tiene todo el andamiaje del HUD: 4 slots, un modo HUD
pausado, un radial de selección, widgets por pantalla y un canal de acciones
(`HudWidgetAction` / `SuitOS.perform_action`). Pero **hoy solo se puede manejar
con teclado y mouse/touch**:

- `hud_slot_1..4` está bindeado **únicamente a las teclas 1–4**, sin ningún
  binding de gamepad.
- El modo HUD (`hud_mode`) abre el radial con TAB y ya tiene el botón 3 (Y) del
  gamepad, pero **no hay forma de elegir un slot, abrir su pantalla, accionar el
  widget ni arrastrarlo** con el mando.
- `RadialSelectorV2` es **estático**: abre y cierra sin transición, sin tween de
  hover, sin feedback de confirmación. Se siente como un menú de debug, no como
  una interfaz diégetica del traje.
- Los items que deberían ser "huddeables" están incompletos: **Criocápsulas** no
  tiene componente HUDable (existen solo como props/parallax).

El resultado: un jugador con gamepad —que es como se juega el vertical slice— no
puede usar el HUD sin soltar el mando.

## Estado actual (lo que ya existe y hay que respetar)

| Pieza | Rol hoy |
|-------|---------|
| `core_v2/input/InputDataV2.gd` | Streamea `hud_mode` (sostenido) y `hud_slot` (1..4 sostenido, 0=ninguno). Tap/hold se decide **en el stream** (umbral 0.4 s) para que el replay no diverja. |
| `core_v2/input/InputProviderV2.gd` | `Mode.LIVE/REPLAY`, `JOY_DEADZONE=0.2`, `digital_camera_enabled` (D-pad como cámara; el modo HUD lo apaga). |
| `core_v2/autoloads/PauseManager.gd` | `pause_hud_mode()` / `resume_hud_mode()` / `is_hud_mode_paused()`: el modo HUD pausa el gameplay. |
| `core_v2/ui/hud/HudModeOverlay.gd` | F3. TAB tap = radial; con pantalla abierta = volver; hold = radial cuasimodo; teclas 1–4 = abrir/cerrar pantalla del slot y hold = radial fijando ese slot. |
| `core_v2/ui/hud/HudSlots.gd` | Reglas y geometría de los 4 slots (`slot_key`, `is_right`, `pin_to`, `slot_position`, `outward_swipe`). 1–2 a la izquierda, 3–4 a la derecha. |
| `core_v2/ui/hud/SuitOSWidgetHost.gd` | F1.5. `HOLD_MSEC=400`, `DRAG_START=12`, swipe-out vacía el slot, hold+drag mueve el widget, zona de reciclaje. Todo por puntero. |
| `core_v2/ui/radial/RadialSelectorV2.gd` | Dial apuntado (no scrolleado), arco 6→3→12, `NONE=-1`, `dead_zone`, `point_at()`, `confirm()`, `cancel()`. Sin animaciones de apertura/cierre. |
| `core_v2/ui/hud/HudWidgetAction.gd` | `perform(from, screen_id, op, args)`; `pointer_on_button()`, `buttons_in()`, `focus_first_button` / `press_focused_button` (navegación GUI por foco). |
| `core_v2/components/HUDableComponent.gd` | Alta/baja automática en SuitOS; `hud_view_scene`, `hud_widget_scene`, `hud_screen_id/title/icon`, `default_relevance`, `allowed_actions_list`. |
| `project.godot` §[input] | `hud_mode` = Tab + joypad botón 3. `hud_slot_1..4` = teclas 1–4 **solamente**. |

Índices de gamepad en el proyecto (Godot 3): `0=A, 1=B, 2=X, 3=Y, 4=LB/L1, 5=RB/R1,
6=LT/L2, 7=RT/R2, 8=Back, 9=Start, 10=L3, 11=R3, 12–15=D-pad`.

## Solution

### 0. Modelo de tres capas

Todo el diseño sale de separar tres capas que **no se pisan**:

| Capa | Cuándo | Hombros (L1/R1/L2/R2) | Botones de cara (A/B/X/Y) |
|------|--------|------------------------|----------------------------|
| **Juego** | siempre por defecto | acción (zoom/run/roll/modo de multi-tool/gatillos) | juego (saltar, agacharse, interactuar, habilidad Cargol) |
| **HUD** | modo HUD activo (mundo en pausa) | **slots 1..4** | radial / cancelar / confirmar |
| **Pantalla** | una pantalla abierta | slots 1..4 (tap = cambiar de pantalla) | **funciones del widget** |

La capa Juego **no se toca**. Es la decisión central de esta FD: ver
*Decisión de diseño* abajo.

### 1. Mapeo de botones

**1.1 Slots (capa HUD y Pantalla).** Se agregan bindings de gamepad a las
acciones existentes, sin renombrarlas:

```
hud_slot_1 → joypad botón 4  (LB / L1)
hud_slot_2 → joypad botón 6  (LT / L2)
hud_slot_3 → joypad botón 5  (RB / R1)
hud_slot_4 → joypad botón 7  (RT / R2)
```

Se conserva el orden visual de `HudSlots`: **1 y 2 a la izquierda, 3 y 4 a la
derecha**. Por eso L1/L2 = 1/2 y R1/R2 = 3/4, y no el orden de la lista.
Mantener la correspondencia "hombro del lado = slot del lado" es lo que hace
legible el mapeo sin tutorial.

Se respeta el patrón del proyecto: `deadzone = 0.5` en cada evento, igual que
`hud_mode`.

**1.2 `hud_mode`.** Ya tiene el botón 3 (Y). Se mantiene. En la capa HUD se le
suman dos usos nuevos (radial y salir) descritos en §2.

**1.3 Botones de cara en modo pantalla.** A/B/X/Y se leen como `ui_accept`
(A), `ui_cancel` (X) y como los botones declarados por el widget (§3). No se
agregan acciones nuevas al mapa: la pantalla declara sus operaciones y el overlay
las despacha por `HudWidgetAction`.

### 2. Entrada y salida de la capa HUD

- **Tap de `hud_mode` (Y)** → entra a la **capa HUD** (sticky). El mundo queda en
  pausa por `PauseManager.pause_hud_mode()` (comportamiento actual). Dentro, los
  hombros son slots.
- **Tap de `hud_mode` de nuevo**, o **X (`ui_cancel`)**, o **B sobre el radial sin
  selección** → sale de la capa HUD y vuelve al juego.
- **Hold de `hud_mode`** → radial *cuasimodo* (como hoy): se mantiene abierto
  mientras el botón esté apretado y al soltar se elige lo marcado.
- Con **una sola pantalla registrada** no se abre radial: el tap de slot abre
  directo (regla que ya aplica el overlay hoy).

La capa HUD **sticky** (en vez de modificador sostenido) es deliberada: el mundo
ya está en pausa, así que no hay coste de gameplay en dejarla abierta, y evita el
"claw" de sostener Y + hombro + stick al mismo tiempo.

### 3. Tap y hold de slot

En la capa HUD, **tap de un hombro**:

- Slot **con** pantalla asignada → se abre su pantalla (modo pantalla).
- Tap del mismo slot con su pantalla ya abierta → se cierra (vuelve al jugador).
- Slot **vacío** → **el tap no hace nada** (no se abre el radial). El slot
  responde con un *deny*: haptic corto de rechazo, la etiqueta del hombro (§9)
  parpadea en ámbar y el marco del slot vacío se ilumina un instante. Un tap no
  debe abrir un menú: el radial es una acción deliberada.

En la capa HUD, **hold de un hombro**:

- Slot **vacío** → abre el radial **fijado a ese slot** para asignarle una
  pantalla (`_begin_hold_radial(slot)`), con feedback visual de hold (§3.1).
- Slot **con** pantalla → abre el radial fijado a ese slot para **cambiarla**
  (comportamiento actual de `_begin_hold_radial(slot)`); si además el stick se
  mueve, ese mismo hold levanta el widget para arrastrarlo (§6).

Se reusa tal cual la ruta existente `HudModeOverlay._feed_slot_gesture()` /
`_tap_slot()` / `_begin_hold_radial()`. **No se duplica lógica**: el gamepad solo
alimenta `input.hud_slot`, y el overlay hace lo de siempre. El único cambio real
respecto de hoy es que el tap de un slot vacío deja de abrir el radial.

#### 3.1 Feedback visual de hold (obligatorio)

El hold no puede ser invisible: el jugador tiene que ver que la pulsación "está
cargando" antes de que aparezca el radial.

| Progreso del hold | Qué se ve |
|-------------------|-----------|
| 0 ms (down) | La etiqueta del hombro (§9) se enciende y el marco del slot sube de brillo. |
| 0→400 ms | El marco del slot se **llena** como una barra circular/horizontal en cian (el mismo lenguaje del dial), proporcional a `t/HOLD_MSEC`. |
| 400 ms | El anillo se cierra: haptic (`Haptics.pulse(LIFT_MSEC)`), flash breve del marco y **recién ahí** entra el radial con la animación de apertura de §8. |
| Soltar antes | El marco se vacía hacia atrás (~0.12 s) y no pasa nada. |

Es el mismo umbral que ya usan el radial y el widget (`HOLD_MSEC` / `DRAG_HOLD_MSEC`
= 400 ms), así que se siente como un único gesto en todo el HUD. El relleno es
puramente visual y no lee input: no afecta el determinismo (§11).

### 4. Modo pantalla: los 4 botones controlan funciones del widget

Se define un **contrato nuevo y opcional** en las pantallas HUDables:

```gdscript
# HUDableComponent.gd (aditivo, default vacío = sin cambio de comportamiento)
func hud_gamepad_actions() -> Array:
    # [{ "button": "a"|"b"|"x"|"y", "op": String, "label": String,
    #    "icon": String, "enabled": bool, "confirm": bool }]
    return []
```

Reglas:

- El overlay consulta `hud_gamepad_actions()` de la pantalla activa **en cada
  cambio de snapshot** y pinta una **leyenda diégetica** (§8).
- Al oprimir un botón de cara, el overlay despacha
  `HudWidgetAction.perform(self, screen_id, op, {})` → `SuitOS.perform_action()`.
  Es la misma ruta que el botón táctil del widget, así que **funciona igual en
  local y en control remoto** (F4 valida `op` contra `allowed_actions_list`).
- Si la pantalla **no** declara acciones, se usa la ruta GUI que ya existe:
  D-pad/stick mueven el foco (`focus_first_button`) y A confirma
  (`press_focused_button`).
- Caso de referencia (linterna, FD-298): `hud_gamepad_actions()` devuelve
  `[{"button":"a","op":"toggle","label":"Encender/Apagar","confirm":true}]`.
  A = toggle, sin entrar ni salir de nada.
- Ningún botón de cara hace *fire* en modo pantalla: el mundo está en pausa y la
  capa es de UI.

### 5. Acorde rápido (sin entrar a modo pantalla)

**Hold de un hombro + tap de un botón de cara** = ejecuta la operación del widget
**sin abrir su pantalla**.

- El **hold** del hombro ya abre el radial fijado a ese slot (comportamiento
  actual de `_begin_hold_radial(slot)`).
- En vez de confirmar (que abriría la pantalla), el botón de cara con
  `"confirm": true` ejecuta **la operación primaria** de la pantalla del slot:
  `HudWidgetAction.perform(..., op, {})`.
- El radial **no se cierra**: el slot sigue en foco para encadenar más acciones.
  Se cierra al soltar el hombro, o con X/B.
- **Feedback obligatorio**: haptic (`Haptics.confirm()`), flash del sector del
  radial (§7) y actualización del widget del slot en el mismo frame. Sin
  feedback, el acorde es invisible.

Ejemplo pedido: `hold R1 (slot 3) + tap A` → toggle de la linterna, sin abrir la
pantalla de la linterna.

### 6. Hold de un hombro → drag/drop con el stick

**Hold del hombro + movimiento del stick** levanta el widget de ese slot y lo
arrastra, igual que hoy lo hace el mouse/touch en `SuitOSWidgetHost`.

- El vector del stick entra por `input.move_vec` (ya está en el stream y ya lo usa
  el radial vía `HudModeOverlay._drive_from_stream()`).
- Se reusa la ruta de drag existente: `show_drop_targets(true, slot_at(pos))`,
  resaltado del slot destino, y `pin_to_slot()` al soltar. **El stick sustituye al
  puntero, no la lógica.**
- Se mantiene `DRAG_START` (12 px equivalentes) y `HOLD_MSEC` (400 ms) del host
  para que el gesto se sienta idéntico al del mouse.
- **Soltar fuera de un slot** → el widget vuelve a su slot (no se pierde).
- **Soltar sobre la zona de reciclaje** (`recycle_rect()`) → se vacía el slot
  (mismo comportamiento que el mouse).
- Si el stick está centrado, el "fantasma" del widget sigue al cursor virtual
  anclado al centro del slot; el stick lo desplaza desde ahí.
- En modo pantalla, el hold+drag sirve además para **anclar la pantalla abierta a
  otro slot** (ruta `_drop_view()` que ya existe).

### 7. Radial: navegación con gamepad

`RadialSelectorV2` ya se apunta con un vector; falta cerrar los bordes del mando:

1. **Snap al soltar.** Con el stick, soltar en el centro no debe dejar "nada
   seleccionado". Se agrega: al soltar el hombro/`hud_mode`, si `_hover_index ==
   NONE` pero hubo un último hover válido, se confirma ese último hover (memoria
   corta de 1). Si nunca hubo hover, no se confirma nada y el radial queda
   abierto.
2. **Navegación discreta por D-pad.** Además del stick, D-pad Arriba/Abajo recorre
   las opciones del arco (equivalente a los stops del `ElevatorFloorSelector`),
   para quien prefiere pasos. El modo HUD ya apaga `digital_camera_enabled`, así
   que el D-pad está libre.
3. **Cancelación explícita.** X (`ui_cancel`) y B cancelan (`_selector.cancel()`),
   con el mismo retract de cierre que §7.4.
4. **Haptics de hover.** Cuando `option_hovered` cambia de índice, un pulso corto
   (`Haptics.pulse`). Hoy solo vibra la confirmación.

### 8. Radial: animaciones (pedido explícito)

Hoy `open()` y `close()` solo hacen `visible = true/false`. Se especifica un set
de animaciones **visuales, no deterministas** (dependen de estado, nunca de
entrada; el replay no las ve):

| Momento | Animación |
|---------|-----------|
| Apertura | El anillo **se despliega** desde el centro del dial: `scale` 0.85→1.0 y `modulate.a` 0→1 en ~0.16 s, con los sectores saliendo en cascada (delay escalonado por índice, ~0.02 s). |
| Idle | **Pulso holográfico** sutil del anillo (`modulate.a` 0.85↔1.0, ~1.6 s, loop). Barato: un solo `Tween` sobre el contenedor, sin tocar el shader por frame. |
| Hover | El sector enfocado crece ~4 % y sube su brillo (~0.10 s, `TRANS_CUBIC/EASE_OUT`). El texto de la opción se desliza al readout central (ya existe `announce_readout_text`, se conserva). |
| Confirmar | **Flash** del sector elegido (blanco→color base, ~0.20 s) + haptic + el dial se retrae antes de que la pantalla entre. |
| Cerrar/cancelar | Retract **hacia el centro** (`scale` 1.0→0.88, `a`→0, ~0.12 s) y recién ahí `visible = false`. |
| Entrada de pantalla | La pantalla entra desde el origen del slot que la abrió (ya hay `view_transition_origin()` de FD-297: se reusa el origen). |

Notas de implementación: todo con `Tween` sobre contenedores (patrón ya usado en
`_readout_tween`), sin `_process` por frame ni cambios de shader. Con `render_scale
< 1` el overlay ya pide `hold_full_resolution_ui()` (F3), así que las animaciones
no se ven pixeladas.

### 9. Descubribilidad: leyenda y etiquetas de slot

Un mapeo de mando que no se ve, no existe. Dos elementos diégeticos:

- **Leyenda de modo pantalla**: fila de 4 pastillas abajo de la pantalla abierta,
  una por botón de cara con `label`/`icon` de `hud_gamepad_actions()`. Se oculta
  a los ~3 s y vuelve al primer input (mismo patrón que las leyendas de
  interacción existentes).
- ~~**Etiqueta de hombro en cada widget de slot** (`L1`/`L2`/`R1`/`R2`)~~ —
  **retirada (Sebastián, 2026-09-19): el mapeo de hombros se descubre jugando, no
  se rotula.** `SuitOSWidgetHost._draw_shoulders()` queda solo para el rechazo de
  un slot vacío (feedback de acción, FD-304 §3).

### 10. Criocápsulas como item huddeable (prioridad)

Las criocápsulas existen **solo como props/parallax** (`core_v2/props/criopod/*`,
bakeadas por `DomeIntro_CriopodsSource`). No tienen componente HUDable.

**10.1 `CryoPodsHUDable.gd`** (`extends HUDableComponent`, nuevo):

- `hud_screen_id = "ship:cryopods"`, `hud_screen_title = "CRIOCÁPSULAS"`.
- Se monta en la bahía de criocápsulas de `Dome_Intro` (junto a
  `DomeIntro_CriopodsSource`), **una sola instancia** que agrega las cápsulas; no
  una por cápsula (registrar 28 `Pod_NN` no aporta nada al jugador).
- `hud_view_scene` = escena nueva `CryoPodsView.tscn` que **reusa
  `CryoDiagnosticsUI`** (`core_v2/things/CryoDiagnosticsUI.gd`) y
  `DomeIntroCryoDiagnosticsDisplay.tscn` como base: ya saben recolectar y
  aplicar snapshot (`collect_state()` / `update_snapshot()`) y ya viajan al
  control remoto.
- `hud_widget_scene` = `CryoPodsWidget.tscn` (nuevo): roster de cápsulas con
  ocupante, estado y alerta. Sin lógica propia: solo dibuja `widget_snapshot()`.
- `widget_snapshot()` (JSON-safe): `{ id, title, pods: [ {id, occupant,
  status, vitals, alarm} ], alarms: int }`.
- `relevance()`: base baja; sube fuerte si hay **alguna cápsula en alarma**
  (mismo patrón que `SystemStatusScreen` con `STATE_FALLO`).
- `allowed_actions_list = ["scan", "select"]` (MVP). `perform_action("scan",
  {"pod": id})` devuelve telemetría de esa cápsula; `select` fija el foco del
  roster. `eject`/`wake` quedan **fuera de scope** (Acto II).
- `hud_gamepad_actions()`: A = `scan` de la cápsula enfocada, X = salir,
  D-pad/stick = recorrer el roster. Con esto las criocápsulas se manejan igual
  con mando, mouse y control remoto.

**10.2 Siguientes huddeables** (mismo contrato, tickets separados): Sistemas de
nave (`ShipSystemBus` F2), migración de Cargol a pantalla (F2), Multi-tool y
Linterna (ya existen). La lista vive en el registry de `SuitOS`, no en código
nuevo.

### 11. Determinismo y replay

Regla dura: **ninguna decisión de diseño puede depender de estado no grabado.**

- Los hombros entran al stream como `hud_slot` (1..4) y el modo como `hud_mode`.
  El overlay sigue decidiendo tap/hold **con las muestras grabadas**
  (`HudTabGesture`), no con `OS.get_ticks_msec()` sobre el input en vivo.
- El acorde y el drag se resuelven **en el overlay**, no en el proveedor: el
  proveedor solo traduce botones a acciones.
- Las animaciones (§8) son puramente visuales y no leen input: no afectan el
  replay.
- El mapeo de hombros → slots se prueba con `test_hud_mode.gd` en modo REPLAY
  inyectando un `InputProviderV2` con muestras sintéticas.

## Decisión de diseño (resuelta 2026-09-18)

**El conflicto:** los cuatro hombros **ya están tomados** en gameplay:

| Botón | Acciones actuales |
|-------|-------------------|
| LB (4) | `zero_g_roll_left`, `zoom_in`, `tool_next_mode` |
| RB (5) | `zero_g_roll_right`, `zoom_out`, `run`, `tool_prev_mode` |
| LT (6) | `tool_fire_secondary` |
| RT (7) | `tool_fire_primary` |

No se pueden mapear R1/R2/L1/L2 a slots **y** conservar fire/zoom/run/roll sin
resolver el choque.

### Considered Options

- **Opción A — Hombros = slots solo en la capa HUD (recomendada).**
  El botón HUD (Y) entra a la capa HUD sticky; dentro, los hombros son slots.
  Gameplay intacto, cero riesgo de regresión, reusa `hud_slot`/`hud_mode` y todo
  el código de las teclas 1–4 tal cual.
  *Pros:* no toca nada validado; el mundo ya está en pausa, así que no cuesta
  nada dejarla abierta; un solo lugar donde vive la regla.
  *Cons:* el flujo es `Y → hombro`, una pulsación más que lo descrito.

- **Opción B — Hombros siempre = slots; reasignar gameplay.**
  Liberar los cuatro hombros moviendo `run`/`zoom` a L3/R3 o al D-pad, `roll` a
  L3/R3 (solo zero-G) y fire a los gatillos... que son justamente 2 de los 4
  slots. **No cierra**: fire no tiene a dónde irse sin empeorar el aim.
  *Pros:* el flujo exacto que pediste.
  *Cons:* rompe muscle memory, obliga a revalidar zero-G, cámara y multi-tool;
  no hay destino razonable para `tool_fire_primary/secondary`.

- **Opción C — Hombros = slots según estado de manos.**
  Manos libres (multi-tool guardado) → hombros = slots; multi-tool alzado
  (aim) → hombros = fuego/zoom/run. Es diegético ("el traje libera el HUD cuando
  no estás apuntando").
  *Pros:* directo como pediste y sin botón extra.
  *Cons:* `run` y `zoom` se usan **caminando**, no solo apuntando; habría que
  reasignarlos igual. Agrega un modo que el jugador debe aprender.

- **Seleccionada: A** (decidido por Sebastián, 2026-09-18), porque es la única
  que no rompe gameplay ya validado y la única implementable sin reasignar fire.
  El flujo queda `Y → hombro`, y el botón HUD ya está mapeado, así que no se
  agrega ningún binding nuevo de entrada/salida.

Consecuencias de elegir A, explícitas:

- `run`, `zoom`, `roll` (zero-G), `tool_next_mode`/`tool_prev_mode` y
  `tool_fire_primary/secondary` **no se tocan**.
- Los hombros solo significan "slot" dentro de la capa HUD. Fuera de ella, el
  mando se comporta exactamente como hoy.
- La regresión a vigilar (§Verification 10) es que la capa HUD no se quede
  "pegada": salir con Y o X debe devolver los hombros al gameplay en el mismo
  frame.

## Fuera de scope

- Reasignación completa de controles de gameplay (solo entra si se elige C).
- Recarga de batería de linterna (ya en backlog de FD-298).
- `eject_pod` / `wake_pod` en criocápsulas (Acto II).
- Rebind del jugador / menú de controles.

## Files to Modify

- `project.godot` — bindings de gamepad a `hud_slot_1..4` (modificar).
- `core_v2/ui/hud/HudModeOverlay.gd` — botones de cara en modo pantalla, acorde
  rápido, drag con stick, cancelación con X/B (modificar).
- `core_v2/ui/hud/HudWidgetAction.gd` — despacho de `hud_gamepad_actions()` y
  operación primaria para el acorde (modificar).
- `core_v2/components/HUDableComponent.gd` — `hud_gamepad_actions()` default
  vacío (modificar).
- `core_v2/ui/radial/RadialSelectorV2.gd` — snap al soltar, navegación por D-pad,
  haptics de hover, animaciones de apertura/idle/hover/confirm/cierre
  (modificar).
- `core_v2/ui/hud/SuitOSWidgetHost.gd` — etiqueta de hombro por slot, drag
  alimentado por stick (modificar).
- `core_v2/things/FlashlightScreen.gd` — declarar `hud_gamepad_actions()`
  (modificar, caso de referencia).
- `core_v2/things/CryoPodsHUDable.gd` — nuevo.
- `core_v2/ui/hud/CryoPodsWidget.tscn` / `.gd` — nuevos.
- `core_v2/things/CryoPodsView.tscn` — nuevo (reusa `CryoDiagnosticsUI`).
- `core_v2/levels/interiors/Dome_Intro.tscn` — montar `CryoPodsHUDable`
  (modificar).
- `core_v2/tests/test_hud_mode.gd`, `test_hudable.gd`,
  `test_suitos_widget_host.gd`, `test_radial_selector.gd` — casos nuevos
  (modificar).
- `docs/features/FEATURE_INDEX.md` — alta de FD-304 (modificar).

## Verification

1. **Bindings.** `project.godot` mapea L1/L2/R1/R2 a `hud_slot_1..4` con
   deadzone 0.5; `InputDataV2` los ve como `hud_slot` 1..4 en modo LIVE.
2. **Abrir pantalla.** Tap de Y y luego tap de R1 abre la pantalla del slot 3;
   tap otra vez la cierra.
3. **Slot vacío.** Tap de un hombro vacío → no pasa nada, con deny (haptic +
   parpadeo ámbar de la etiqueta). Hold de ese hombro → relleno visual del marco
   durante 400 ms y recién ahí el radial fijado a ese slot.
4. **Feedback de hold.** El relleno del marco es proporcional al tiempo y se
   revierte al soltar antes del umbral.
5. **Modo pantalla.** Con la pantalla de linterna abierta, A hace toggle y el
   `widget_snapshot()` refleja `on: true` en el mismo frame.
6. **Acorde.** `hold R1 + tap A` alterna la linterna **sin** abrir su pantalla, con
   haptic y flash del sector.
7. **Drag con stick.** `hold R1 + stick` levanta el widget, resalta el slot bajo
   el stick y al soltar sobre otro slot queda re-pinneado; soltar fuera lo
   devuelve; sobre la zona de reciclaje vacía el slot.
8. **Radial.** Soltar el stick en el centro confirma el último hover (no "nada");
   X/B cancelan con retract; el hover vibra al cambiar de opción.
9. **Animaciones.** Apertura en cascada, pulso idle, hover, flash de confirmación
   y retract de cierre visibles; con `render_scale < 1` no se pixelan.
10. **Criocápsulas.** `CryoPodsHUDable` aparece en el registry de SuitOS en
    `Dome_Intro`; su widget lista cápsulas; `relevance()` sube con una cápsula en
    alarma; `scan` devuelve telemetría; el mismo widget responde en el control
    remoto (F4).
11. **Determinismo.** `test_hud_mode.gd` en REPLAY reproduce un guion de
    hombros + botones de cara y da el mismo resultado que en LIVE.
12. **Regresión.** Partida a pie con mando: L1/L2/R1/R2 siguen haciendo
    zoom/run/roll/modo de multi-tool **fuera** de la capa HUD.

## Open Questions

Ninguna bloqueante. Pendientes menores de implementación:

1. ¿El *deny* del tap en slot vacío (§3) vibra en todas las plataformas o solo
   donde ya hay haptics (`Haptics.gd`)? Se decide al implementar, no cambia el
   spec.
2. ¿La leyenda de modo pantalla (§9) se muestra también con mouse/teclado, o
   solo cuando el último input fue gamepad? Recomendado: solo gamepad, para no
   ensuciar el HUD de quien juega con teclado.

## Implementación (2026-09-19)

Entregado al final, como pedía FD-306 §8. Todo lo de §1–§10 está, con estas
cuatro diferencias, las cuatro por conflictos reales entre secciones:

1. **§7.1 (snap al soltar) se quitó.** El hub de FD-306 §1 hace que
   `_index_at()` nunca devuelva "nada marcado", así que la memoria corta no
   tenía caso que atender. Ver FD-306 §Implementación.
2. **§6 y §3 se pisaban sobre el mismo gesto.** Se resolvió por estado del
   slot: con el hombro sostenido sobre un slot **lleno**, el stick arrastra su
   widget y la **cruceta** (§7.2) recorre el arco para cambiarle la pantalla;
   sobre un slot **vacío** no hay nada que arrastrar y el stick apunta el
   dial. Cada gesto significa una sola cosa en cada momento.
3. **El hold deshace el `_open_on_press`.** Una pantalla que es solo widget se
   abría al oprimir la tecla del slot (no hay transición de cámara que
   disimule la espera). Que la pulsación termine siendo un hold dice que no
   era eso lo que se quería, así que se cierra antes de abrir el dial — si no,
   el acorde de §5 abría justo la pantalla que promete no abrir.
4. **La cruceta entró al stream como `hud_nav`** (−1/0/+1), igual que
   `hud_mode` y `hud_slot` y por el mismo motivo (§11): el auto-repeat se
   cuenta con muestras grabadas. `from_dict()` lo lee con guarda, así que los
   replays viejos siguen cargando.

### §10 Criocápsulas — alcance real

`CryoPodsHUDable` es **una** pantalla por bahía (`ship:cryopods`), montada en
`Dome_Intro` junto al `ShipSystemBus`, con widget de roster, `scan`/`select`,
`relevance()` que sube fuerte con una cápsula en alarma y `hud_gamepad_actions()`.

Dos cosas se hicieron distinto a §10.1, a propósito:

- **No hay `CryoPodsView.tscn`.** §10.1 proponía reusar `CryoDiagnosticsUI`,
  pero esa pantalla es telemetría de sala (coolant, válvulas, fugas), no ficha
  de ocupante — lo dice el propio FD-307. La bahía queda como pantalla de solo
  widget (patrón ya soportado: el widget ampliado es la vista). La ficha por
  cápsula es de FD-307, que la diseñó.
- **El roster nace sin ocupantes declarados.** El componente los soporta
  (`pod_roster`, líneas `"id|ocupante|estado"`), pero la escena sólo declara
  `pod_count = 28`: inventar 28 nombres de tripulación es escribir narrativa,
  no implementar el sistema. Mientras no haya roster, el widget dice
  "28 CÁPSULAS · NOMINAL" en vez de afirmar "0/28 OCUP", que sería falso.
  La alerta **no se inventa**: sale del `criocoolant` del `ShipSystemBus`.

`X = salir` de §10 no se declara como acción de la pantalla: salir es de la
capa HUD (X/B), no una operación del widget, y declararla obligaría a inventar
un `op` que no hace nada.

### Descubribilidad (§9)

Queda la leyenda de botones de cara bajo la pantalla abierta, **sólo con un mando
conectado**: con teclado es ruido (Open Question 2, resuelta así).

Las etiquetas de hombro `L1`/`L2`/`R1`/`R2` **se retiraron el 2026-09-19**
(Sebastián): el mapeo de hombros se descubre jugando. `_draw_shoulders()` sólo
dibuja el rechazo de un slot vacío.
