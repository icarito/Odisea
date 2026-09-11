# FD-298: Pantalla de linterna (batería retro + toggle en el widget)

**Status:** Design
**Priority:** P1
**Effort:** Small
**Created:** 2026-09-11
**Parent:** FD-296 (OdiseaOS) / FD-280 (linterna de casco)

## Problem

La linterna de casco (FD-280, implementada) se enciende y apaga con
`toggle_flashlight`, pero **no existe en la UI**: el jugador no ve cuánta carga
le queda ni tiene forma de accionarla sin conocer el teclado.

Para un sistema que corre en el traje (OdiseaOS) la linterna debería ser una
pantalla más: un **slot de HUD** con un indicador de batería **tipo retro**, y un
**botón** en el widget para encenderla y apagarla (útil sobre todo en móvil y en
el Control Remoto, donde no hay teclado).

## Solution

**1. Estado de batería en la linterna (aditivo a FD-280).**
`HelmetFlashlight` hoy no tiene batería. Se le agrega, sin cambiar su
comportamiento por defecto:

```gdscript
export(float) var battery_max := 100.0
export(float) var battery_drain_per_second := 0.4   # solo con la linterna encendida
export(float) var battery_low_threshold := 20.0
var battery := battery_max
signal battery_changed(value: float, max_value: float)
```

Reglas:
- La batería **solo** baja con la linterna encendida; apagada no consume.
- A 0 se apaga sola (un solo `toggle()`), emite `battery_changed` y queda
  apagable hasta recargar (recarga = backlog, ver Out of Scope).
- `battery_changed` se emite con cambio significativo (no cada frame, para no
  saturar señales).

**2. Pantalla registrable `FlashlightScreen` (`HUDableComponent`).**
- `hud_screen_id = "player:flashlight"`, `hud_screen_title = "LINTERNA"`.
- `widget_scene` = `FlashlightWidget`; `view_scene` = vista completa con el
  medidor grande y el estado.
- `allowed_actions = ["toggle"]` y `perform_action("toggle")` llama a
  `HelmetFlashlight.toggle()`. Con eso el botón funciona **igual en local y en
  remoto** (FD-296 F4 valida `remote_action` contra `allowed_actions`).
- `widget_snapshot()` (JSON-safe): `{ id, title, on: bool, battery: float,
  battery_max: float, low: bool }`.
- `relevance()`: sube si la linterna está encendida y sube **fuerte** si
  `battery` está por debajo de `battery_low_threshold`.

**3. `FlashlightWidget`: indicador retro + botón.**
- **Indicador de batería tipo retro**: barra de segmentos (estilo pila/celda de
  los 80) que se vacía por segmentos, no un número. Color de aviso cuando queda
  por debajo del umbral. Sin animación costosa: cambios discretos.
- **Botón de encendido/apagado** dentro del widget: emite
  `perform_action("toggle")` por `SuitOS`, nunca llama a la linterna directo
  (así el mismo widget sirve en el teléfono).
- El widget es **solo lectura + un botón**: sin lógica de batería propia.

**4. Slot.** La pantalla vive en el sistema de slots de FD-296 (Slot A
automático / Slot B fijado). No se crea slot nuevo.

## Files

- `core_v2/props/lights/HelmetFlashlight.gd` (additive: batería + señal)
- `core_v2/things/FlashlightScreen.gd` / `.tscn` (new)
- `core_v2/ui/hud/FlashlightWidget.gd` / `.tscn` (new)
- `core_v2/tests/test_flashlight_screen.gd` (new)
- `docs/features/FEATURE_INDEX.md` (modify)

## Verification

1. En `Dome_Intro`, encender la linterna: el widget muestra el indicador retro
   lleno y el estado encendido; apagarla lo refleja.
2. Dejar la linterna encendida: la batería baja y el indicador se vacía por
   segmentos; por debajo del umbral entra en color de aviso.
3. A 0 la linterna se apaga sola y no vuelve a encender hasta recargar (recarga
   fuera de scope).
4. El **botón del widget** enciende y apaga la linterna (local). En remoto, el
   mismo botón viaja como `remote_action{"op":"toggle"}` y funciona (requiere
   F4).
5. La relevancia sube con la batería baja: el slot automático prioriza linterna
   sin abrir nada.
6. Snapshot JSON-safe: `widget_snapshot()` no incluye objetos de Godot (test).
7. `python3 scripts/check_tracked_imports.py` y smoke de imports limpios.

## Out of Scope

- **Recarga** de la batería (estaciones, celdas, items). Backlog.
- Batería como recurso de puzzle o de sigilo.
- Sonido de encendido, parpadeo del haz por batería baja (pulido posterior).
- Cambiar el comportamiento óptico de la linterna (FD-280 intacto).
