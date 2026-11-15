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

## Alcance del commit actual

Cambios aditivos y off por defecto (riesgo de regresión ~nulo):
- `BootLoader.gd`: export `startup_world_scene_path`, target de arranque, `_attach_menu_overlay()`.
- `Menu.gd`: `overlay_mode`, `configure_world_overlay()`, `_start_in_overlay()`, `_on_arrival_hide_overlay()`, `_close_overlay_and_give_control()`.
- Este doc de sesión.

## Verificación

- Tests legacy del menú (`test_menu_checkpoint_flow`) y suites de transición/seamless verdes (el modo overlay no altera el flujo por defecto).
- Falta: corrida de juego real (desktop/web) para validar overlay, cámara y memoria.
