# FD-313: Fixes de ergonomía del HUD, determinismo y paridad del Control Remoto (FD-294/296 F4)

**Status:** Planned
**Priority:** P1
**Effort:** Medium
**Created:** 2026-09-20
**Parent:** FD-294 (Control Remoto) · FD-296 F4 (Control Remoto como cliente HUD) · FD-304 (Gamepad Diégetico) · FD-305 (Drawer) · FD-306 (Radial Fixes)
**Relacionadas:** `docs/engineering/casos-uso-FD304-305-306.md` · `docs/engineering/gui-map-2026-09-20.md`

---

## 1. Resumen y Contexto

Tras la entrega de los **FD-304, FD-305 y FD-306** (gamepad diégetico, drawer de apps y fixes del radial), la interfaz local de OdiseaOS en PC cuenta con un sistema completo de slots, radiales y drawers.

Sin embargo, una revisión del sistema completo revela dos necesidades principales:
1. **Fixes de Ergonomía y Determinismo Local**: Solucionar conflictos de entrada con teclado (`Espacio` colisionando con `ui_select` y `jump`), falta de navegación por flechas, salida brusca en mouse y unificar el tiempo de hold a contadores de ticks deterministas (`InputDataV2`).
2. **Paridad y Alineación del Control Remoto (FD-294 / FD-296 F4)**: Asegurar que la pantalla móvil o cliente remoto (`RemoteControlHome.gd` / `RemoteHudBackend.gd`) funcione con paridad visual y funcional respecto a la interfaz local, documentando formalmente las diferencias deliberadas por arquitectura.

---

## 2. Hallazgos y Fixes de la Interfaz Local

### 2.1 Conflicto de Tecla `Espacio` (`project.godot`)
- **Problema**: `Espacio` está mapeado en `project.godot` a `ui_select` (scancode 32) y a la física de salto (`jump`). En el dial radial, al presionar `Espacio`, la UI intenta confirmar la selección a la vez que `_dismiss_radial()` o `_input()` intentan cancelar o reaccionar a salto.
- **Fix**: Remover scancode 32 de `ui_select`. `ui_select` debe ser `Enter`, mientras que `ui_accept` (Enter / Joypad A) queda como la confirmación universal.

### 2.2 Navegación por Flechas de Teclado
- **Problema**: `ui_up`, `ui_down`, `ui_left`, `ui_right` no se consumen en `HudModeOverlay.gd` ni `InputProviderV2.gd` para paso discreto en dial o drawer (sólo D-pad con `hud_nav`).
- **Fix**: Conectar `ui_up`/`ui_down` a la señal `hud_nav` o consumo interno para navegación paso a paso en teclado.

### 2.3 Ergonomía de Mouse y Rueda
- **Problema**: En `SuitOSDrawer.gd`, un clic fuera de las filas no cierra la vista (`row < 0: return`), dejando al usuario de mouse atascado sin botón explícito de retroceso salvo la tecla `Tab`. Además, la rueda del mouse (`BUTTON_WHEEL_UP/DOWN`) no desplaza la lista.
- **Fix**: Interpretar clic neutro fuera del panel como volver/cancelar, y mapear la rueda al scroll inercial del drawer.

### 2.4 Determinismo en Tiempos de Gestos (Hold / Swipe)
- **Problema**: Mientras `HudTabGesture.gd` cuenta 24 ticks del stream determinista, `SuitOSWidgetHost.gd` y `HudModeOverlay.gd` usan `OS.get_ticks_msec()` para medir los 400 ms de hold y thresholds de drag.
- **Fix**: Migrar mediciones de tiempo de gestos de HUD a contadores de ticks basados en `InputDataV2` para garantizar replays 100% deterministas.

---

## 3. Modelo de Paridad y Diferencias del Control Remoto

El Control Remoto (`RemoteControlHome.gd`) utiliza `RemoteHudBackend.gd` como un backend *duck-typed* de `SuitOS.gd`. Esto permite instanciar localmente en el dispositivo remoto los mismos nodos de UI (`SuitOSWidgetHost.tscn` y `HudModeOverlay.tscn`).

### 3.1 Diferencias Deliberadas (Diseñadas por Arquitectura)

| Aspecto | Local (PC Host) | Remoto (Teléfono / Cliente) | Razón de Diseño |
|---|---|---|---|
| **Pausa de Mundo** | Entrar al HUD pausa la partida (`PauseManager.pause_hud_mode()`). | El HUD remoto corre **en vivo sin pausar** la partida del Host. | Permitir al compañero operar sistemas mientras el jugador se mueve en PC. |
| **Pase de Slots** | Slots 1–4 guardados en `SuitOS` (`_pinned`). | Adopta los slots del Host una sola vez al conectar; luego la disposición es **local e independiente** en el cliente. | El teléfono organiza su pantalla sin desacomodar la barra de acceso de la PC. |
| **Vistas 3D / Presentador** | `HudViewMount.gd` con shader 3D `HoloScreen2D` y cámaras de foco. | Muestra la vista en 2D Viewport si existe escena 2D estática; si no, amplía el `widget_scene` a pantalla completa. | El dispositivo remoto no renderiza la escena 3D ni la cámara del Host. |
| **Intercepción de Input** | Teclado/Mando manejan al personaje o al HUD según la capa activa. | Reenvía joystick analógico y botones al Host via WebSocket; suprime A/B/X al Host únicamente cuando el dial radial remoto está abierto. | Previene saltar/agacharse accidentalmente en la PC al seleccionar una app en el móvil. |

---

## 4. Huecos y Mejoras en el Control Remoto (Faltantes de Paridad)

### 4.1 Favoritos y Orden del Radial en Remoto (FD-305 / FD-306)
- **Brecha**: `SuitOSRemoteBridge.gd` envía `screen_list`, pero **no** envía los `favorite_screens` ni la bandera `favorites_initialized` de `SuitOS`. `RemoteHudBackend.gd` no tiene la lista de favoritos curados, por lo que el dial remoto muestra el registry completo sin aplicar la curaduría ni los 6 favoritos máximos.
- **Solución**: Enviar directiva `favorites` al emparejar y al cambiar favoritos en Host. `RemoteHudBackend` almacena favoritos y los utiliza en su `HudModeOverlay`.

### 4.2 Transmisión de Iconos (`hud_screen_icon`)
- **Brecha**: `screen_list` en el bridge no transmite el icono de pantalla ni `hud_gamepad_actions` completos en todas las rutas.
- **Solución**: Incluir `icon` y `gamepad_actions` en la entrada de `screen_list` para que el proxy remoto los exponga al dial y a las leyendas.

### 4.3 Acorde Rápido Remoto (Hold Hombro + A)
- **Brecha**: `HudSlotGamepadV2` se ejecuta en `RemoteControlHome.gd`, pero cuando se dispara un tap/acorde desde un hombro remoto, debe despacharse la directiva `remote_action` al Host si la pantalla no está abierta.
- **Solución**: Asegurar que `HudSlotGamepadV2` utilice `perform_action()` de `RemoteHudBackend`, el cual envía la acción validada por `remote_action` al Host.

### 4.4 Reflejo del Estado de Pausa del Host
- **Brecha**: Cuando el Host entra en pausa rápida (tecla Start o `PauseManager.toggle_quick_pause()`), el bridge notifica `host_paused`. `RemoteControlHome.gd` muestra "PARTIDA EN PAUSA" y bloquea `send_remote_action`. Falta verificar que al despausar se reanude fluidamente el refresco de snapshots.

---

## 5. Plan de Verificación

1. **Pruebas de Ergonomía Local**:
   - Abrir el dial radial con teclado y presionar `Espacio`: no debe haber doble acción ni cierres no deseados (confirmación limpia con `Enter`).
   - Usar flechas de teclado Arriba/Abajo para navegar opciones del dial y filas del drawer.
   - Probar clic del mouse fuera de las filas del drawer: debe retornar ordenadamente al dial.
2. **Pruebas de Control Remoto**:
   - Conectar cliente remoto a sesión Host: verificar que `slots` iniciales coincidan y luego permitan reordenarse independientemente en remoto.
   - Marcar favoritos en el Host (FD-305): comprobar que la lista de favoritos se refleje en el radial del cliente remoto.
   - Ejecutar acciones remotas (ej: alternar linterna desde el teléfono): verificar actualización instantánea de snapshot en Host y cliente remoto.
3. **Tests Automatizados**:
   - `test_remote_control_home_hud.gd`
   - `test_suitos_remote_bridge.gd`
   - `test_hud_drawer.gd` y `test_hud_mode.gd`

