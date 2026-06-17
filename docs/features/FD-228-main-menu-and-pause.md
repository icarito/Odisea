# FD-228 — Menú Principal con Pantalla de Pausa (UI del Juego)

## Problema

Odisea tiene `scenes/Menu.tscn` y `core_v2/ui/Menu.gd` pero no se usan en producción: la app arranca directo a BaseTerrace sin pasar por ningún menú. Tampoco existe una pantalla de pausa — Escape solo captura/suelta el mouse. El jugador no tiene forma de:
- Elegir "Nueva Partida" o "Continuar"
- Ver versión del juego
- Acceder a opciones (volumen, controles)
- Salir al menú principal desde el juego
- Pausar la partida (congelar el mundo)

## Requerimientos

### 1. Menú Principal funcional

El `Menu.tscn` existente se refactoriza para ser la escena inicial del juego (primer escena en Project Settings). Debe:

- Mostrar título "ODISEA" con el font actual (Heading_Font.tres) + subtítulo "EL ARCA SILENCIOSA"
- Mantener la preview 3D animada de CoverScene (Viewport con escena 3D rotando).
- Botones (en VBoxContainer, estilo actual):

| Botón | Acción |
|-------|--------|
| **NUEVA PARTIDA** | Inicia el juego (`BaseTerrace.tscn` o punto de inicio por defecto) |
| **CONTINUAR** | Solo visible si existe un save (revisar SaveManager/SessionManager para save data). Carga el último checkpoint. |
| **OPCIONES** | Abre la pantalla de opciones (ver sección 3) |
| **SALIR** | Cierra el juego |

- Los botones deben tener texto (no solo iconos) y ser navegables con teclado (flechas + Enter).
- Soporte para mando: UI navegable con stick/DPad + A (InputMap actions "ui_up", "ui_down", "ui_accept").
- Fade in al cargar (ya existe en Menu.gd). Fade out al iniciar partida.

### 2. Pantalla de Pausa

Nueva escena PauseMenu como overlay. Se abre con Escape cuando el mouse ya está capturado (en juego):

```
┌──────────────────────────────┐
│        ── PAUSA ──           │
│                              │
│    [▶ REANUDAR]             │
│    [↺ REINICIAR NIVEL]      │
│    [⚙ OPCIONES]             │
│    [⌂ MENÚ PRINCIPAL]       │
│    [✕ SALIR]                │
│                              │
│   Versión: 0.3.0-ff17c82b   │
└──────────────────────────────┘
```

- Fondo: negro semi-transparente (alpha 0.6) con un sutil viñeteado.
- `get_tree().paused = true` al abrir. PauseMenu tiene `pause_mode = PAUSE_MODE_PROCESS`.
- Opciones del overlay usa el mismo sistema de opciones que el menú principal.
- Escape togglea: si abierto → cierra. Si cerrado → abre.
- Clickear fuera del panel central cierra la pausa (si está visible).

**Atajo**: se instancia desde un Autoload (`PauseManager.gd`) que escucha Escape globalmente. Si el juego está corriendo y el mouse está capturado → abre PauseMenu. Si el menú principal está visible → no interfiere (no instancia).

### 3. Pantalla de Opciones

Nuevo overlay o escena separada. Accesible desde menú principal y desde pausa:

```
┌──────────────────────────────┐
│         ── OPCIONES ──       │
│                              │
│   AUDIO                      │
│   [▮▮▮▮▮▮▮▮▯▯] Volumen Gral │
│   [▮▮▮▮▮▯▯▯▯▯] Música       │
│   [▮▮▮▮▮▮▮▯▯▯] SFX          │
│                              │
│   CONTROLES                  │
│   [▮▮▮▮▯▯▯▯▯▯] Sensibilidad │
│   [✓] Invertir Y             │
│   [✓] Vibración              │
│                              │
│   VIDEO                      │
│   [Fullscreen] ▼             │
│   [1920x1080] ▼              │
│   [✓] V-Sync                 │
│                              │
│   [← VOLVER]                 │
└──────────────────────────────┘
```

- Sliders: usar `HSlider` + Label con valor numérico al lado.
- Dropdowns: usar `OptionButton`.
- Toggles: usar `CheckButton`.
- Los cambios a volumen se aplican en tiempo real (`AudioServer.set_bus_volume_db`).
- Guardar preferencias: `ConfigFile` en `user://settings.cfg`.
- Cargar al inicio desde un Autoload `SettingsManager.gd`.

### 4. Botón "Continuar" con detección de save

- `SaveManager` (o `SessionManager`) expone `has_save()`.
- Si no hay save, el botón CONTINUAR está deshabilitado / oculto.
- Si hay save, muestra texto "CONTINUAR" y carga la última escena guardada.

### 5. Integración: flujo completo

1. App inicia → `MainMenu.tscn` (refactorizado desde `Menu.tscn`).
2. Jugador elige NUEVA PARTIDA → fade out → carga `BaseTerrace.tscn`.
3. Durante el juego, Escape suelta el mouse. Segundo Escape → abre PauseMenu.
4. En PauseMenu: REANUDAR → captura mouse, cierra overlay.
5. MENÚ PRINCIPAL → descarga la escena actual, carga MainMenu.
6. SALIR → cierra el juego.

### 6. Control por mando

- Todo el menú es navegable con InputMap: `ui_up`, `ui_down`, `ui_accept`, `ui_cancel` (para volver).
- Los focus neighbours están configurados en los botones.
- Los sliders responden a ui_left/ui_right.
- En PauseMenu, `ui_cancel` (B en mando, Escape en teclado) cierra el overlay.

### 7. Consistencia visual

- Misma paleta que el menú principal: fondos oscuros, texto en ámbar/claro.
- Mismo font (Heading_Font.tres para títulos, font mono para cuerpo).
- Animación de fade (Tween) en transiciones entre menú/pausa/opciones.
- Sin ruido visual: es una nave espacial, no una interfaz de juego de móvil.

## Archivos a modificar/crear

| Archivo | Cambio |
|---------|--------|
| `scenes/Menu.tscn` | Refactorizar a MainMenu: botones con texto, subtítulo, layout responsive |
| `core_v2/ui/Menu.gd` | Refactorizar: detectar save, conectar nuevo CONTINUAR, opciones |
| `core_v2/ui/PauseMenu.tscn` | **Nuevo**: overlay de pausa |
| `core_v2/ui/PauseMenu.gd` | **Nuevo**: lógica de pausa, opciones, botones |
| `core_v2/ui/OptionsMenu.tscn` | **Nuevo**: pantalla de opciones (compartida desde menú y pausa) |
| `core_v2/ui/OptionsMenu.gd` | **Nuevo**: sliders, toggles, dropdowns, ConfigFile I/O |
| `core_v2/autoload/SettingsManager.gd` | **Nuevo**: autoload que carga `user://settings.cfg` al inicio |
| `core_v2/autoload/PauseManager.gd` | **Nuevo**: autoload que escucha Escape global y gestiona pausa |
| `core_v2/autoload/SaveManager.gd` | **Modificar** (si existe) o crear: exponer `has_save()` |
| `project.godot` | Cambiar escena inicial a `res://scenes/Menu.tscn` |

## Out of scope

- Menú de carga de partidas (elegir entre varios slots)
- Customización de controles (remapping de teclas)
- Perfiles de jugador
- Menú de accesibilidad
- Multi-idioma
- Background parallax o animaciones complejas del menú (el CoverScene actual es suficiente)

## Dependencias

- `SaveManager` / `SessionManager.has_save()` — si no existe, CONTINUAR se oculta y se implementa en otro FD.
- `SettingsManager` — escribir e integrar sin romper AudioManager existente.

## Criterio de Aceptación

1. Al iniciar el juego, se ve el Menú Principal con título, preview 3D, y botones navegables.
2. NUEVA PARTIDA → transición fade → carga BaseTerrace.
3. Durante el juego: Escape suelta mouse. Escape otra vez → PauseMenu overlay con fondo semi-transparente. Juego congelado.
4. PauseMenu: REANUDAR funciona. OPCIONES abre el overlay de opciones. VOLVER cierra.
5. Opciones: sliders cambian volumen en tiempo real. Fullscreen toggle funciona. Se persisten al reiniciar.
6. Si hay save → CONTINUAR visible. Si no → oculto/deshabilitado.
7. MENÚ PRINCIPAL desde pausa → descarga escena actual, carga menú.
8. Navegación con teclado (flechas + Enter) y mando.
9. Sin crashes, sin errores en consola.
