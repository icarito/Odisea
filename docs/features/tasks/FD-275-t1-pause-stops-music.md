# FD-275 T1: La música debe detenerse en el menú de pausa (brief para Jules)

## ⚠️ ANTES DE EMPEZAR — Godot 3 vía apt (obligatorio)

En Odisea SIEMPRE hay que instalar Godot 3 con `apt` antes de correr cualquier test.
El proyecto es **Godot 3.x** (`project.godot` con `config_version=4`), no Godot 4.
Verificá que `godot` (o `godot3` / `godot3-bin`) esté en el PATH y sea 3.x antes de
ejecutar el runner. Si no está, instalalo con apt y recién después corré los tests.

Runner de tests (GdUnit3): `./runtest.sh -a ./core_v2/tests/` (headless). El output
siempre se guarda en `./reports/gdunit_runner.log`; si no ves salida en terminal,
leé ese archivo (`grep -E "(PASSED|FAILED|ERROR|Total)" ./reports/gdunit_runner.log`).

## Contexto — qué está mal

Hoy la BGM **solo se silencia al perder el foco de la ventana** (alt-tab / cambio de
app), vía `NOTIFICATION_WM_FOCUS_OUT` en `AudioManager.gd`. Pero al abrir el **menú de
pausa** (Esc / `ui_cancel`) con `PauseManager`, la música **sigue sonando**.

Comportamiento deseado: al pausar (menú de pausa), la BGM se detiene; al reanudar,
se reanuda desde donde estaba. Hoy no pasa.

## Defecto localizado

- `PauseManager.pause()` / `_finish_pause()` hacen `get_tree().paused = true`, pero
  **nunca le avisan a `AudioManager`** que pare la música.
- `AudioManager` ya tiene TODA la maquinaria de pausa/retoma de BGM, pero solo la
  dispara por foco de ventana:
  - `_set_music_focus_paused(bool)` (flag `_music_paused_by_focus`)
  - `_pause_internal_bgm_players()` (usa `set_stream_paused(true)` y guarda
    `_zone_playback_positions`)
  - `_resume_internal_bgm_players()` (reanuda y llama `_update_bgm()`)
- Resultado: pausar con Esc no afecta la música; solo el alt-tab la mutea.

## Dirección del fix (sin código — vos lo implementás)

- Exponer en `AudioManager` un API público de pausa de música por menú (hoy
  `_set_music_focus_paused` es privado y el flag se llama `_music_paused_by_focus`;
  la lógica interna ya existe y es correcta). Por ejemplo un método público
  `set_music_paused_by_menu(bool)` que reutilice `_pause_internal_bgm_players()` /
  `_resume_internal_bgm_players()`.
- Hacer que `PauseManager.pause()` llame a ese API al pausar y `resume()` lo llame al
  reanudar.
- **Idempotencia**: el flag `_music_paused_by_focus` también gatea `_update_bgm()` y
  `_crossfade_to()`. Hay que asegurar que no quede el estado "pegado" si se pausa y
  luego se pierde foco (o viceversa) en órdenes distintos. Mantener los dos disparadores
  (foco y menú) independientes y combinables sin dejarse un flag activo de más.

## Archivos implicados

- `core_v2/autoloads/AudioManager.gd` (exponer API público de pausa por menú)
- `core_v2/autoloads/PauseManager.gd` (llamar al API en `pause()`/`resume()`)

## Reglas

- Godot 3.x / GDScript 1.x: `yield`, nunca `await`. Sin `@onready`.
- No romper el comportamiento existente de foco (alt-tab sigue silenciando).
- No tocar `get_tree().paused` (eso lo maneja `PauseManager`); solo coordinar audio.

## Criterio de aceptación

1. Al abrir el menú de pausa (Esc), la BGM se detiene.
2. Al reanudar, la BGM se reanuda desde la posición guardada (misma zona).
3. Alt-tab (pérdida de foco) sigue silenciando/pausando como antes, sin regresiones.
4. Pausar y perder foco en cualquier orden no deja la música en estado inconsistente.
5. `./runtest.sh -a ./core_v2/tests/` no rompe las pruebas existentes (especialmente
   `TestAudioLogic.gd`).

Cuando termines, publicá el PR contra `main` con el spec y el diff. **No mergear sin OK explícito.**
