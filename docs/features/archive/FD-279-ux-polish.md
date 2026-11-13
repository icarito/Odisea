# FD-279: UX polish — resize, foco sin menú, sombras de andamio, PerformanceMonitor

Cuatro fixes de UX/rendimiento, sin assets nuevos.

## T1: Redimensionar ventana no debe mover el mouse caóticamente (#11)

**Archivo:** `core_v2/autoloads/SessionManager.gd` (y/o `core_v2/player/PlayerControllerV2.gd`)

**Problema:** al redimensionar la ventana con el mouse en CAPTURED, Godot emite un `InputEventMouseMotion` sintético con un `.relative` enorme (el warp al centro), que se lee como un salto de cámara. Ya existe `_ignore_next_mouse_motion` en `PlayerControllerV2.gd` (comentario en línea ~241) que descarta ese primer motion tras `set_mouse_mode(CAPTURED)`, pero NO se aplica al redimensionar.

**Cambio:** en el handler de `NOTIFICATION_WM_SIZE_CHANGED` (código 1008 en Godot 3.x), si el mouse está CAPTURED, marcar la bandera de ignorar el próximo motion (o equivalente) para descartar el salto fantasma.

## T2: Pérdida de foco → pausa SIN PauseMenu; reaparece al recuperar foco (#12)

**Archivo:** `core_v2/autoloads/PauseManager.gd`

**Problema:** `_pause_on_focus_loss()` llama a `pause()`, que instancia y muestra el `PauseMenu`. Lo pedido: al perder foco, pausar el árbol pero SIN mostrar el menú; al recuperar el foco (FOCUS_IN), recién ahí mostrar el menú (manteniendo la pausa).

**Cambio:** añadir flag `_paused_by_focus`. En FOCUS_OUT: `get_tree().paused = true` + mouse visible, sin instanciar el menú, marcando `_paused_by_focus = true`. En FOCUS_IN: si `_paused_by_focus`, instanciar/mostrar el menú (mantener pausa). Al `resume()`, limpiar la flag.

**Nota de coordinación:** FD-275 (PR #304, aún sin mergear) también toca `PauseManager.gd`. Esta T2 se escribe sobre la versión actual de `trunk`; si FD-275 se mergea antes, hay que reconciliar ambas ediciones de `PauseManager.gd` en la rama de integración.

## T3: Las plates industriales de los andamios no reciben sombras (#14)

**Archivo:** `core_v2/props/scaffold/SteelGratePlatform.gd` (verificar también `ScaffoldHubRing.gd`)

**Problema:** los `MeshInstance` generados proceduralmente (deck, frame, tubos, paneles) no fuerzan `cast_shadow`; el hazard strip explícitamente lo apaga (línea 691). Las superficies tipo "diamond plate" (plates industriales) no proyectan ni reciben sombras correctamente.

**Cambio:** asegurar que los meshes generados de la plataforma/andamio usen `cast_shadow = SHADOW_CASTING_SETTING_ON` (el deck de rejilla alpha-scissor debe usar el modo de sombra que respete el alfa, p.ej. `SHADOW_CASTING_SETTING_ON` con material de sombra o double-sided). Verificar el material `diamondAluminum.tres` (no unshaded, debe recibir). Investigar el caso exacto y corregir para que las plates reciban y proyecten sombras.

## T4: PerformanceMonitor no debe gatillarse en transiciones ni en pausa (#16)

**Archivo:** `core_v2/autoloads/PerformanceMonitor.gd`

**Problema:** `_process()` corre siempre (`pause_mode = PROCESS`) y muestra warnings de CPU / lag spikes también durante las transiciones de escena (que naturalmente bajan FPS) y durante la pausa.

**Cambio:** al inicio de `_process()` (o antes del bloque de warnings), si `get_tree().paused` es true, o si `SceneManager` reporta `is_transitioning() == true`, omitir el muestreo/emisión de warnings (o resetear el baseline de frame gap para no disparar un falso positivo al salir).

## Constraints
- Godot 3.x / GDScript 1.x.
- PR contra `trunk` (sin mergear sin OK explícito de Sebastián).
- Cada T independiente y verificable en aislamiento.
