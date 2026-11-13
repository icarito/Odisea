# FD-230 — Menú Principal y Pantalla de Pausa

## Problema

Odisea tiene `scenes/Menu.tscn` y `core_v2/ui/Menu.gd` pero no se usan. La app arranca directo al juego. No hay pantalla de pausa — Escape solo suelta el mouse.

## Requerimientos

### 1. Menú Principal (refactorizar Menu.tscn)
- Escena inicial del juego (cambiar project.godot).
- Título "ODISEA" con Heading_Font, subtítulo "EL ARCA SILENCIOSA".
- Preview 3D rotando (CoverScene, ya existe en Menu.tscn).
- Botones: NUEVA PARTIDA, CONTINUAR (solo si hay save), OPCIONES, SALIR.
- Navegable con teclado (ui_up/ui_down/ui_accept) y mando.
- Fade in/out (ya existe en Menu.gd).

### 2. Pantalla de Pausa (nueva)
- Se abre con Escape cuando el mouse está capturado (en juego).
- `get_tree().paused = true`. Overlay con pause_mode = PAUSE_MODE_PROCESS.
- Botones: REANUDAR, REINICIAR NIVEL, OPCIONES, MENÚ PRINCIPAL, SALIR.
- Escape togglea: abre si cerrado, cierra si abierto.
- Versión del juego visible (ProjectSettings "application/config/version").

### 3. Pantalla de Opciones (nueva, desde menú y pausa)
- Sliders: Volumen general, Música, SFX (HSlider + Label).
- Toggles: Invertir Y, Vibración (CheckButton).
- Dropdowns: Fullscreen, Resolución, V-Sync (OptionButton).
- Cambios en tiempo real (AudioServer.set_bus_volume_db).
- Guardar en `user://settings.cfg` (ConfigFile). Cargar desde autoload SettingsManager.

### 4. Autoloads nuevos
- `SettingsManager.gd` — carga `user://settings.cfg` al inicio.
- `PauseManager.gd` — escucha Escape global, instancia PauseMenu overlay.

### 5. Archivos
- `scenes/Menu.tscn` — refactorizar.
- `core_v2/ui/Menu.gd` — refactorizar (save detection, connect buttons).
- `core_v2/ui/PauseMenu.tscn` + `.gd` — nuevo.
- `core_v2/ui/OptionsMenu.tscn` + `.gd` — nuevo.
- `core_v2/autoload/SettingsManager.gd` — nuevo.
- `core_v2/autoload/PauseManager.gd` — nuevo.
- `project.godot` — cambiar escena inicial a Menu.tscn.
