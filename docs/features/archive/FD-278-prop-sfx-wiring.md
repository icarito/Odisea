# FD-278: Cableado de SFX en props (válvula, coolant, botón)

Tres props que hoy no emiten sonido. Usar el patrón existente `SFXComponentV2` (`core_v2/components/SFXComponentV2.gd`), que es un `AudioStreamPlayer3D` con `sound_name`, `trigger_mode` y auto-conexión a las señales `activated` / `deactivated` / `interaction_started` del padre.

**Assets ya existen en `assets/sfx/`.** Los nombres abajo son DEFAULTS que Sebastián puede cambiar; Jules solo cablea.

## T1: Sonido de válvula (PipeValve)

**Archivo:** `core_v2/props/pipe/PipeValve.tscn` (o su `.gd` si la escena no existe)

**Problema:** `PipeValve.gd` (extiende `InteractableBaseV2`, hereda señales `activated`/`deactivated`) no reproduce sonido al girar.

**Cambio:** añadir un hijo `SFXComponentV2` con:
- `sound_name = "valve"`
- `trigger_mode = "OneShotInteract"` (o "Interact" si no existe; ver enum del componente)
- `stream` = un SFX metálico corto (default: `assets/sfx/metal2.wav`)

## T2: Sonido coolant on/off (PipeCoolantRun)

**Archivo:** `core_v2/props/pipe/PipeCoolantRun.gd`

**Problema:** `PipeCoolantRun.gd` (extiende `Spatial`, NO interactable, no tiene señales `activated`) controla el flujo con `set_flow_intensity()` y hace la transición en `_physics_process()`, pero no emite sonido al encender/apagar.

**Cambio:** en `_physics_process()`, detectar el cruce del umbral de encendido/apagado (cuando `_current_flow_intensity` pasa de `<= 0.0001` a `> 0.0001` y viceversa) y reproducir un sonido de "steam hiss" al encender y un golpe corto al apagar. Usar un `AudioStreamPlayer3D` local con `bus = "SFX"`.

- Encender: default `assets/sfx/steam hiss.wav`
- Apagar: default `assets/sfx/metal1.wav` (corto)

**Importante:** no disparar sonido cada frame — solo en la transición. Usar una bandera interna del estado sonoro previo.

## T3: Sonido de botón pedestal (PedestalButton)

**Archivo:** `core_v2/props/controls/PedestalButton.tscn`

**Problema:** `PedestalButton.gd` (extiende `PropBaseV2` → `InteractableBaseV2`, hereda señales `activated`/`deactivated`) no suena al pulsar.

**Cambio:** añadir un hijo `SFXComponentV2` con:
- `trigger_mode = "OneShotInteract"`
- `stream` = un click corto (default: `assets/sfx/click.wav`)

## Constraints
- Godot 3.x / GDScript 1.x.
- PR contra `trunk`.
- Test: cada prop reproduce su sonido al interactuar/cambiar estado; el coolant suena al encender y al apagar, no en loop.
- Si algún default de asset no gusta, es un cambio de una línea — no bloquear el merge por eso.

## Referencias
- Patrón: `core_v2/components/SFXComponentV2.gd`
- `core_v2/props/pipe/PipeValve.gd` (señales `activated`/`deactivated`, signal `valve_state_changed`)
- `core_v2/props/pipe/PipeCoolantRun.gd` (no interactable, usa `set_flow_intensity`)
- `core_v2/props/controls/PedestalButton.gd` (interactable)
- Assets: `assets/sfx/` (metal1/metal2.wav, click.wav, "steam hiss.wav")
