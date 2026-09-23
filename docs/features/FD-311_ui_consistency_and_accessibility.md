# FD-311: Consistencia de Capas, Navegación y Accesibilidad de UI en OdiseaOS y Módulos HUDdables

**Status:** Implemented (v1)  
**Priority:** High  
**Effort:** Medium  
**Created:** 2026-09-23  
**Completed:** 2026-09-23  

---

## 1. Contexto y Análisis de Módulos Actuales

En *Odisea: El Arca Silenciosa*, la interfaz de usuario abarca pantallas generales del sistema (menús, avisos de privacidad y consentimientos), controles táctiles/móviles, widgets de estado del traje (`SuitOS`) y módulos HUDdables interactivos en el mundo 3D (`RingHub_Level`, interiores de nave):

- **`CryoPodHUDable` / `CryoPodTerminal`** (FD-307): Gestión de la criocápsula, diagnóstico de constante vital y control de escotilla.
- **`FlashlightHUDable` / `PantallaLinterna`** (FD-298): Control de potencia, patrón de haz e indicadores de batería de la linterna.
- **`DomeIntroCryoDiagnosticsDisplay` / `CryoPodsHUDable`**: Diagnóstico general de estado de la bahía de criopods.
- **`HoloTerminalHUDable` / `HoloTerminalV2`**: Terminales holográficas interactivas de pared y mesa con soporte de cámara cinematográfica.
- **`SuitOS` / `SuitOSWidgetHost`** (FD-304 / FD-305 / FD-306): Dial radial de favoritos, accesos directos, barra de estado y soporte de mandos.
- **`InteractableContextWidget`** (FD-310): Prompts contextuales en HUD al apuntar a objetos interactivos.

---

## 2. Problem (Huecos de Consistencia y Accesibilidad)

A partir de la revisión interactiva en vivo y de las pruebas en la compilación HTML5 / desktop, se identificaron los siguientes huecos de diseño e integración:

### 2.1 Jerarquía Dispersa de Capas (`CanvasLayer`)
Diferentes componentes de UI utilizaban números de capa arbitrarios (`50`, `60`, `100`, `105`, `115`, `120`, `128`, `1000`, `2000`, `3000`, `4096`), ocasionando que:
- Los overlays de consentimientos y avisos de privacidad taparan el ratón virtual.
- Cuadros de UI anidados en otros `CanvasLayer` fueran ignorados o dibujados por debajo del fondo del popup en Godot 3.

### 2.2 Desorientación del Puntero Virtual en Arranque (Gamepad / Web)
- Al abrir popups sin movimiento de ratón previo (o en plataformas táctiles / gamepad), la coordenada `(0, 0)` situaba el puntero virtual fuera del margen visible superior izquierdo (`-7, -10`).
- El uso de llamadas postergadas (`attach_popup_deferred`) generaba 1 cuadro de atraso durante el cual la UI aparecía sin cursor activo.

### 2.3 Ergonomía de Navegación y Foco con Gamepad/Teclado
- En módulos HUDdables (`CryoPodHUDable`, `PantallaLinterna`), la pérdida o deshabilitación dinámica de botones enfocados (ej. inhabilitar botones durante cargas de escena) dejaba la navegación en gamepad sin feedback claro o con el foco perdido.

### 2.4 Bloqueo de Puntero en Navegadores (HTML5 Prewarm Stall)
- Durante la compilación síncrona de shaders en WebGL, mantener la captura de puntero (`MOUSE_MODE_CAPTURED`) provocaba que el usuario percibiera la pestaña del navegador como congelada o bloqueada.

### 2.5 Frecuencia y Descarte del Aviso de Versión Nativa (HTML5 Shell)
- El banner de sugerencia de app nativa en `odisea_shell.html` reaparecía constantemente y requería descarte manual explícito incluso tras haber iniciado partida.

---

## 3. Solution (Solución e Integración Realizada)

### 3.1 Espectro Unificado de Capas (`CanvasLayer Spectrum`)
Se establece una norma estricta de capas para todo el proyecto:

| Rango de Capa | Componente / Sistema | Descripción y Comportamiento |
|---|---|---|
| **0 – 49** | UI 3D en Mundo | Interfaces locales en Viewports de props |
| **50 – 99** | Menú de Pausa (`PauseManager`) | Menú de pausa del juego y ajustes de partida |
| **100 – 119** | `MobileUIManager` | Controles virtuales táctiles en dispositivos móviles |
| **120 – 199** | `SuitOSWidgetHost` | Slots de widgets de estado y avisos contextuales (FD-310) |
| **200 – 999** | Overlays Narrativos | Subtítulos, diálogos y notificaciones temporales |
| **1000** | `TransitionLayer` | Fundidos de cambio de escena (`SceneManager`) |
| **2000** | `FirstRunConsentLayer` | Pantallas de protocolo, avisos de privacidad y popups de sistema |
| **4096** | `HoloTerminalViewportInput` | Entrada del viewport de terminales holográficas |
| **10000** | **`VirtualMouseLayer`** | **Puntero virtual unificado (Capa superior absoluta)** |

### 3.2 Estándar de `VirtualMouse` y Centrado Inteligente
- **Ubicación en Raíz Absoluta**: `VirtualMouseLayer` vive directamente colgado de `get_tree().root` en la capa `10000`.
- **Centrado de Respaldo**: Al activar `desktop_mouse_mode` sin una posición conocida (o en `Vector2.ZERO`), el puntero se posiciona automáticamente en el centro geométrico del Viewport (`viewport.size * 0.5`).
- **Vinculación Inmediata**: En `FirstRunConsent.gd` y popups principales, el cursor se acopla inmediatamente en `_ready()` mediante `attach_popup(self)`.

### 3.3 Gestión de Puntero Web y Frecuencia de Notificaciones
- **Liberación de Ratón en Prewarm**: `ShaderWarmupTrigger.gd` y `SceneManager.gd` fuerzan `Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)` en HTML5 durante los hooks de precarga y compilación de shaders.
- **Descarte Automático y Frecuencia Diaria**: `odisea_shell.html` almacena la fecha en `localStorage` (`odisea_native_notice_last_date`) para desplegar el aviso nativo **máximo 1 vez por día**.
- **Ocultamiento al Iniciar Partida**: `Menu.gd` invoca `JavaScript.eval("window.OdiseaShell.hideNativeNotice()")` al presionar *"Nueva Partida"* o *"Continuar"*, ocultando el aviso sin requerir clic manual del usuario.

### 3.4 Consistencia en Módulos HUDdables (Accesibilidad)
- **Safe Focus**: Los módulos HUDdables (`CryoPodHUDable`, `PantallaLinterna`, HoloTerminals) garantizan `grab_focus()` en su control principal apenas el módulo se torna visible.
- **Resiliencia de Foco**: Si el control enfocado es inhabilitado por lógica del juego, el foco migra automáticamente al siguiente control interactivo libre.

---

## 4. Archivos Modificados e Integrados

- [VirtualMouse.gd](file:///run/media/icarito/DATA/icarito/Proyectos/Odisea_Game/src/core_v2/ui/VirtualMouse.gd): Montaje en `root` en capa `10000`, centrado automático si la posición es `Vector2.ZERO`.
- [FirstRunConsent.gd](file:///run/media/icarito/DATA/icarito/Proyectos/Odisea_Game/src/core_v2/ui/FirstRunConsent.gd): Acoplamiento directo de `VirtualMouse.attach_popup(self)` en `_ready()`.
- [Menu.gd](file:///run/media/icarito/DATA/icarito/Proyectos/Odisea_Game/src/core_v2/ui/Menu.gd): Invocación a `hideNativeNotice()` al arrancar la partida y limpieza de orden de capas.
- [ShaderWarmupTrigger.gd](file:///run/media/icarito/DATA/icarito/Proyectos/Odisea_Game/src/core_v2/levels/ShaderWarmupTrigger.gd): Liberación de ratón en HTML5 durante compilación.
- [SceneManager.gd](file:///run/media/icarito/DATA/icarito/Proyectos/Odisea_Game/src/core_v2/autoloads/SceneManager.gd): Liberación de ratón en HTML5 durante `pre_load_hook`.
- [odisea_shell.html](file:///run/media/icarito/DATA/icarito/Proyectos/Odisea_Game/src/core_v2/telemetry/html/odisea_shell.html): Rate limit diario (`localStorage`) y exposición de API `hideNativeNotice`.

---

## 5. Verificación

1. **Pruebas Automatizadas**:
   ```bash
   ./.venv/bin/pytest tests/test_odisea_runner.py -k "test_privacy_consent or test_virtual_mouse"
   ```
   *Resultado:* 100% Passed.

2. **Verificación Visual y Jerarquía**:
   - `VirtualMouseLayer` se mantiene en capa `10000` sobre `FirstRunConsentLayer` (`2000`).
   - El puntero virtual es visible y clickeable desde la primera pantalla de *"Protocolo de abordaje"* (`IntroPanel`).
   - En compilación Web, la sugerencia de descarga nativa desaparece al iniciar la partida y no reaparece durante el mismo día.
