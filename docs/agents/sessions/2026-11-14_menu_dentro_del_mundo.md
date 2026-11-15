# Menú dentro del mundo — bitácora del 2.º PR (2026-11-14)

## Decisión (Sebastián, vía src-49)

- El menú se dibuja sobre la escena 3D viva (la cápsula criogénica / Dome_Intro donde despierta el piloto).
- Nueva partida y Continuar acercan la cámara al piloto y entregan el control sin corte ni pantalla de carga.
- Continuar a otra escena usa el mismo mecanismo seamless con la escena del menú como buffer.
- Solo el arranque en frío (Boot) conserva un fade desde negro.
- Narrativa ambiental: menú mínimo, sin títulos grandes.

## Restricciones y lecciones recibidas

- El cuelgue grande de arranque web eran ~19.3 s en `goto_scene(Menu)` (poll() atómico del loader).
- El warmup de shaders va horneado (`make bake-shader-cache`).
- El menú hoy fuerza resolución completa con `render_scale < 1` (`Menu.gd:84`): en overlay sobre mundo no debe forzarse.
- Medir tiempo de arranque antes/después (desktop y, si se puede, web con Thorium con ventana).
- Tier LOW/Anbernic: el mundo cargado detrás del menú no debe explotar memoria (medir).

## Arquitectura (este PR, esqueleto)

- **BootLoader**: nuevo export `startup_world_scene_path` (vacío = legacy). Si se setea, el boot arranca directo al mundo (fade desde negro permitido) y, al terminar, instancia `Menu.tscn` como **overlay** sobre la escena viva (`_attach_menu_overlay`). Off por defecto: el comportamiento actual queda intacto.
- **Menu.gd**: nuevo modo `overlay_mode` (`configure_world_overlay()`), off por defecto:
  - No fuerza resolución completa (libera `hold_full_resolution_ui`).
  - `_start_in_overlay(scene_path)`: si el destino es el mundo actual (Nueva partida a RingHub, o Continuar al mismo escenario) ⇒ cierra el overlay y entrega control (hardware input on, puntero virtual liberado), sin cambio de escena. Si es otra escena ⇒ `goto_scene` seamless (`transition:"seamless"` + `notify_transition`), con el mundo como buffer; el overlay se oculta al llegar (`scene_ready`).
- **Pendientes (siguiente iteración)**: PauseMenu; estética mínima (quitar títulos grandes / Backdrop sobre mundo); BGM del mundo vs menú; forzar cámara al piloto al entrar (zoom suave); mediciones de arranque (desktop/web) y memoria tier LOW; posible necesidad de tocar PlayerControllerV2 / core_v2/ui/hud (coordinar con src-50).

## Alcance hasta acá (iteraciones)

Cambios aditivos y off por defecto (riesgo de regresión ~nulo):
- `BootLoader.gd`: export `startup_world_scene_path`, target de arranque, `_attach_menu_overlay()`.
- `Menu.gd`: `overlay_mode`, `configure_world_overlay()`, `_start_in_overlay()` (parámetro tipado), `_on_arrival_hide_overlay()`, `_close_overlay_and_give_control()` (ahora también `snap_camera_to_current_state()` al entregar control: cámara al piloto sin corte).
- `PauseMenu.gd`: `MainMenu` muestra el overlay del menú principal si existe (no hace change_scene a Menu); `_find_world_menu_overlay()`.
- Spec: el fade Dome→Hangar quedó anotado como DEUDA (falta buffer de llegada equivalente + cámara continua).
- Este doc de sesión.

## DEUDA explícita (validación con entorno gráfico)

- Mediciones de arranque antes/después (desktop y web/Thorium con ventana) y memoria en tier LOW/Anbernic.
- Capturas visuales del overlay sobre el mundo. Para capturas usar `tools/shot.sh` cuando lo publique src-56, o un Viewport hijo headless; nunca el screenshot del peer. No encender `startup_world_scene_path` por defecto: Sebastián decide cuándo.

## Mediciones de arranque (estado)

El pipeline existe: `StartupTrace` escribe `user://startup_trace.json` (auto-finalize ~30 s o al abrirse el startup gate). Intento headless en este entorno (binario editor + --headless) no completó el arranque (solo eventos de conexión; finalize por timeout) — no es representativo. Falta medición real: desktop (ventana) antes/después y web con Thorium con ventana; y memoria en tier LOW/Anbernic. Metodología propuesta: correr el juego con `startup_world_scene_path` seteado, leer `startup_trace.json` (hitos boot_loader_scene_request → scene_ready → startup_gate) y comparar contra el boot classic.

## Verificación

- Tests legacy del menú (`test_menu_checkpoint_flow`), `test_pause_menu_minimal` y suites seamless verdes en la rama (el modo overlay no altera el flujo por defecto).
- Falta: corrida de juego real (desktop/web) para validar overlay, cámara al piloto, PauseMenu→menú principal y memoria.
