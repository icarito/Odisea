# FD-263: Touch universal — tap para interactuar + detección runtime de controles touch

**Status:** Planned
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-08-16
**Completed:** -

## Problem

Dos carencias relacionadas con la entrada táctil, que hoy dependen de `OS.has_touchscreen_ui_hint() o Android/iOS` (decidido estáticamente en `_ready()`):

1. **El patrón de touch del ascensor no está generalizado.** En `ElevatorFloorSelector` un dedo toca el holograma y funciona. Las válvulas (`PipeValve`) y los botones de pedestal (`PedestalButton`) NO responden a un tap directo: hay que acercarse, esperar el highlight y pulsar el botón "interact" de la UI touch. En pantallas táctiles eso rompe la fantasía de "tocar lo que veo".

2. **Los controles touch no aparecen en Linux táctil.** Hay equipos Linux con pantalla táctil que funcionan, pero como `OS.get_name()` no es Android/iOS y `OS.has_touchscreen_ui_hint()` devuelve false en escritorio, `MobileUIManager` nunca instancia `MobileUI.tscn`. El jugador no tiene joystick virtual, botones ni área de cámara táctil.

## Solution

Un solo frente de infraestructura resuelve ambos: **detectar touch en runtime** (eventos `InputEventScreenTouch` reales) en lugar de decidirlo por plataforma.

### Parte A — Tap directo = confirmar el interactuable resaltado

El ascensor usa un tap *posicional* (elegir un piso de N opciones sobre el holograma). Válvula y botón son `interact()` **binarios**: no eligen opción, confirman el objeto que el jugador ya tiene resaltado (`best_target` en `PlayerControllerV2._process_interaction`).

Generalización: una capa en el controlador (o un nodo de input dedicado) que, ante un `InputEventScreenTouch` corto (tap, no drag) y sin que toque un control de UI existente (`touch_control` / `_is_over_touch_control`), dispara la acción `interact` sobre el target resaltado.

**Restricciones (críticas):**

1. **Determinismo / replay.** NO llamar `interact()` directo desde `_input()`. El tap debe inyectar `interact` en el stream (`InputDataV2.interact`), igual que ya hace `TouchActionButton` con `Input.action_press("interact")`. En reproducción no hay eventos de hardware, así que el camino correcto es el mismo que usa `ElevatorFloorSelector._drive_from_stream()` leyendo `peek_input()`: el tap en vivo se traduce a la misma señal grabable que la tecla F.

2. **Filtro de doble disparo.** `emulate_mouse_from_touch` está en `true` por defecto, así que un tap también emite un click de mouse. Sin filtro, un tap dispara `interact` dos veces (touch + mouse). Reutilizar el patrón `_ignore_emulated_mouse_until` del ascensor (o equivalente global): ignorar el `InputEventMouseButton` que sigue inmediatamente a un `InputEventScreenTouch` ya consumido.

3. **No robar toques a la UI.** El tap solo debe confirmar si el dedo NO cae sobre un control de la capa touch (`TouchActionButton`, joystick, área de cámara). Reutilizar la lógica de `_is_over_touch_control` (grupo `touch_control`).

### Parte B — Controles touch reactivos (Linux táctil incluido)

Cambiar `MobileUIManager` para que deje de depender solo del flag estático:

1. **Detección runtime:** un `_input()`/observer en `MobileUIManager` (o un autoload pequeño) escucha `InputEventScreenTouch`. Al primer toque real → instanciar `MobileUI.tscn` (idem `_spawn_mobile_ui()`), marcar "touch activo" y arrancar un timer de inactividad.

2. **Timer de idle:** cada toque resetea el timer. Si pasan `touch_idle_timeout` segundos sin tocar (p.ej. 15–20s, exportable), ocultar los controles (y soltar el área de cámara táctil para no comerse toques de un ratón/otro uso). Al siguiente toque, reaparecen.

3. **Sincronizar `analog_move_active`.** `InputProviderV2._has_touch_ui()` está cacheada una sola vez (`_touch_ui_hint_resolved`) y es Android/iOS-only; alimenta `analog_move_active`, que decide si el joystick virtual se trata como stick analógico y no como teclas. La detección runtime debe alimentar ese mismo flag (vía un setter o invalidando el cache), o el joystick virtual en Linux táctil se comportará mal.

4. **Preservar el gating existente.** El flag estático actual sigue valiendo para arranque en Android/iOS (arrancar con UI visible). El runtime lo *extiende* (aparece en Linux táctil) y lo *refina* (se oculta tras inactividad prolongada). No romper `refresh_for_pause`, `set_replay_mode`, ni `get_reserved_overlay_margins`.

## Considered Options

- **A. Tap posicional (proyectar ray desde el tap) para cada prop** — caro y rompe el determinismo; además válvula/botón no necesitan elegir posición, solo confirmar. Descartado.
- **B. Tap = confirmar el target resaltado (seleccionado)** — reutiliza el pipeline de proximidad/overlap que ya existe (`best_target`), es determinista si inyecta en el stream, y cubre válvulas, botones, levers y cualquier `interact()`. **Seleccionado.**
- **C. Dos FDs separados** — ambas partes comparten la infra de detección runtime; separarlas duplica trabajo y ramas. Un solo FD. **Seleccionado.**

## Files to Modify

- `core_v2/autoloads/MobileUIManager.gd` (modify) — detección runtime de touch + timer de idle + spawn reactivo.
- `core_v2/input/InputProviderV2.gd` (modify) — exponer/invalidar `_has_touch_ui()` para que el runtime la alimente; asegurar `analog_move_active` correcto.
- `core_v2/player/PlayerControllerV2.gd` (modify) — capa de tap→`interact` (o un nuevo nodo de input `core_v2/ui/TouchInteractLayer.gd` si queda más limpio; decisión de implementación, respetando el contrato de stream/replay).
- `core_v2/ui/MobileUI.gd` / `TouchCameraControls.gd` (modify) — exponer show/hide limpio para el timer de idle, sin fugas de input táctil.
- Nuevo (opcional): `core_v2/ui/TouchInteractLayer.gd` + registrarlo como autoload si se elige la ruta de capa dedicada.

## Verification

1. **Tap en válvula (Android/emulador o pantalla táctil):** acercarse, la válvula resalta, un tap corto la activa/desactiva; un solo toggle (sin doble disparo por mouse emulado).
2. **Tap en botón de pedestal:** ídem, `set_active` se alterna una sola vez por tap.
3. **Replay:** grabar una sesión tocando la válvula y reproducirla; el toggle ocurre en el mismo frame que en vivo (determinismo).
4. **Linux táctil:** con touch real, `MobileUI` aparece; tras `touch_idle_timeout` segundos sin tocar, se oculta; un toque nuevo la hace reaparecer. El joystick virtual mueve como stick analógico (`analog_move_active`).
5. **No regresión:** toques sobre el joystick virtual, botones de acción y área de cámara NO disparan `interact`; el tap sobre un control de UI se respeta.
