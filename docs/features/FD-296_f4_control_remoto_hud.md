# FD-296 F4: Control Remoto como cliente HUD

## Contexto

El stack remoto de FD-294 **ya está en `main`**: `RemoteControlManager`
(autoload), `RemoteControlServer`, `RemoteControlClient`, protocolo con canal
`ui` (`send_ui_directive` / `ui_directive_received`), `RemoteControlHome` (la
pantalla del teléfono, hoy solo avisos de conexión/pausa + botón Salir).

**Esta tarea (F4): el teléfono ve las mismas pantallas del HUD que la PC.**
No transmite ViewportTextures ni nodos: el teléfono **instancia su propio**
`view_scene()`/`widget_scene()` y lo hidrata con snapshots JSON-safe.

El estado remoto es **independiente** del local (la pantalla activa en el
teléfono ≠ la del HUD local). **Sin pausa** en el teléfono: el overlay corre
en vivo, no pausa la partida de la PC.

## Archivos que NO se tocan

- `HoloTerminalV2.gd`
- `RemoteControl*` salvo lo **aditivo** descrito aquí
- `Menu*`, `PauseManager`, cámara
- `project.godot`

## Entregables

### 1. Protocolo — ops nuevos (canal `ui` existente, solo aditivo)

Agregar estos `op`s al canal `ui` del protocolo (`RemoteProtocol.gd` +
`RemoteControlServer.gd` + `RemoteControlClient.gd`). **No se crea canal nuevo.**

| Dirección | `op` | Payload |
|---|---|---|
| host→teléfono | `screen_list` | `[{id, title, relevance}]` al emparejar y al cambiar el registro |
| host→teléfono | `screen_active` | `{id, title, view: "scene"\|"widget", snapshot: {...}}` al cambiar la pantalla remota |
| host→teléfono | `screen_data` | `{id, snapshot: {...}}` (actualización puntual sin cambiar pantalla) |
| host→teléfono | `haptic` | `{kind, intensity}` |
| teléfono→host | `remote_action` | `{screen_id, op, args}` validado contra `allowed_actions` y ejecutado con `perform_action()` |
| teléfono→host | `screen_select` | `{id}` — el radial del teléfono pide empujar esa pantalla |

### 2. Puente SuitOS → RemoteControl (host)

Script nuevo: `core_v2/components/SuitOSRemoteBridge.gd` que se añade como
hijo de `RemoteControlManager` en `_ready()`.

Responsabilidades:
- Escuchar `SuitOS.widget_changed(slot, snapshot)` y `SuitOS.screen_registered`/`unregistered`
- Al emparejarse: enviar `screen_list` con `[{id, title, relevance}]`
- Al cambiar pantalla activa remota: enviar `screen_active` con `view: "scene"` si `screen.view_scene() != null`, si no `"widget"`, más el snapshot
- Escuchar `SuitOS.state_changed` → reenviar `screen_data` sin cambiar de pantalla
- Escuchar `screen_select` del teléfono → `SuitOS.get_screen(id)` + `open_screen(id)` (NO pausa, NO overlay local)
- Escuchar `remote_action` → validar contra `screen.allowed_actions()`, ejecutar `screen.perform_action(op, args)`, devolver resultado
- Escuchar `SuitOS.haptic(kind, intensity)` → `send_ui_directive("haptic", ...)`

### 3. Lado teléfono — `RemoteControlHome.gd` extendido

El `RemoteControlHome.gd` actual muestra avisos de conexión/pausa + botón
Salir. Extender con:

**Widget host (siempre visible):**
- Al recibir `screen_list`, el teléfono instancia `widget_scene()` para
  los slots A/B como hijos de un container (mismo patrón que
  `SuitOSWidgetHost` en el overlay local, pero sin pausa: corre en vivo).
- Se hidratan con snapshots del host.
- Los controles móviles existentes (joystick, cámara por arrastre,
  botón de acción) se mantienen visibles debajo/encima.

**Modo pantalla completa:**
- Radial que reúsa `RadialSelectorV2` (mismo patrón
  `ElevatorFloorSelector` que F3) para elegir pantalla activa. Al
  seleccionar, el teléfono envía `screen_select{id}` al host.
- Al recibir `screen_active` del host, el teléfono instancia
  `view_scene()` y la muestra a pantalla completa. Sin `view_scene()` →
  amplía `widget_scene()` en su lugar.
- El canvas del teléfono **sí** puede ampliar (es suyo, no tiene el
  mundo 3D detrás).
- El radial del teléfono también permite fijar pin local (independiente
  del pin del HUD local en la PC).

**Reglas:**
- El teléfono **no** recibe nodos, texturas ni rutas de escena del host
- Widgets/vista se hidratan con snapshots (JSON-safe, mismo contrato SuitOS)
- El teléfono nunca escribe estado del host salvo `remote_action` (gateado)
- Multisesión → backlog (fuera de scope)

### 4. HUDableComponent — contrato F4 mínimo

Agregar a `HUDableComponent.gd` los métodos que F4 requiere (si no existen ya):

```gdscript
func allowed_actions() -> Array:
    return []  # override en subclases

func perform_action(op: String, args: Dictionary) -> Dictionary:
    return {"ok": false, "error": "not implemented"}
```

`HoloTerminalHUDable` ya tiene `view_scene()`, `widget_scene()`,
`widget_snapshot()`, `screen_title()`, `screen_id()`, `relevance()`. Verificar
que `allowed_actions` y `perform_action` estén disponibles (si no, agregarlos).

### 5. Tests

- `test_suitos_remote_bridge.gd`: puente envía `screen_list` al emparejarse
- `test_remote_control_home_hud.gd`: teléfono instancia widgets y vista
- Test de ida y vuelta: `screen_select` → `screen_active`
- `test_remote_actions.gd`: `remote_action` validado y ejecutado

## Orden de implementación

1. Agregar `allowed_actions`/`perform_action` a `HUDableComponent` si faltan
2. Protocolo: ops nuevos en `RemoteProtocol.gd`
3. `SuitOSRemoteBridge.gd` + integración en `RemoteControlManager`
4. `RemoteControlHome.gd`: widget host + radial + modo pantalla completa
5. Tests

## Base y arquitectura

- **Base:** `feature/FD-296-f1.5-visible-slice` (6747f80f). Esta rama ya
  tiene SuitOS + HoloTerminalHUDable + widget host + modo HUD F1.5.
- El contrato de pantalla (screen_id, widget_snapshot, view_scene, etc.)
  ya existe en `HUDableComponent` y `HoloTerminalHUDable`.
- `SuitOS` emite `widget_changed`, `screen_registered`, `screen_opened`,
  `haptic` — el bridge se suscribe a estas señales.
- `RemoteControlServer.send_ui_directive(op, payload)` ya existe.
- `RemoteControlClient.ui_directive_received(op, payload)` ya existe.
- `RadialSelectorV2` ya existe (usado en ElevatorFloorSelector y F3).