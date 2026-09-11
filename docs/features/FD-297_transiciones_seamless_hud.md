# FD-297: Transiciones seamless hacia la pantalla en cuestión

**Status:** Design
**Priority:** P1
**Effort:** Medium
**Created:** 2026-09-11
**Parent:** FD-296 (OdiseaOS) / FD-294 (Control Remoto)

## Problem

Entrar y salir de una pantalla de OdiseaOS es un corte: el overlay aparece y
desaparece de golpe. Eso rompe la lectura diegética del traje — la UI debería
**llegar** de algún lugar y **volver** a él, no encenderse como una luz.

Además cada tipo de origen pide una transición distinta:

- Una **HoloTerminal** del mundo ya tiene su propia cámara de foco
  (`CinematicSetup/FocusedRig`): la transición natural es hacia **esa** cámara,
  no hacia el casco genérico.
- Un sistema de la nave o un prop ad hoc **no** tiene rig de foco: su lugar
  natural es una **perspectiva en primera persona** durante el modo HUD.

Hoy el modo HUD (F3) resuelve la presentación con un presentador 3D que anima
hacia el casco (spec FD-296 §4) — pero aplica la misma transición a todo, y el
origen del terminal no se distingue del origen "sistema".

## Solution

Una transición **según el origen** del HUDable, decidida por el propio HUDable
y ejecutada por el presentador 3D ya existente (`TerminalHUDBridge` +
presentador *config-only*, ver FD-296 §4). **Sin** sistema de presentación
nuevo: sigue siendo `OverlayUIManager` + el bridge.

### Selección de la transición

| Origen del HUDable | Transición | Implementación |
|---|---|---|
| **HoloTerminal** (`HoloTerminalHUDable`) | Vuela a la **cámara de foco del terminal** (`CinematicSetup/FocusedRig/Camera`, vía `TerminalCameraRig`/`CinematicManager`) | El presentador arranca en la posición del terminal y el bridge anima; el rig de foco lo activa el terminal, no SuitOS |
| **Sistema / prop ad hoc** (sin rig) | **Primera persona** durante el modo HUD (el casco) | El presentador anima desde su posición neutral hasta el casco (`hud_cfg_screen_*`), como en F3 |
| **Remoto (teléfono)** | Sin transición 3D: el teléfono no tiene mundo | Fundido 2D corto en `HudModeOverlay` remoto (FD-294), opcional |

El HUDable declara su origen con un método nuevo **aditivo** en
`HUDableComponent`:

```gdscript
# Devuelve {} si no hay origen especial (=> transición a primera persona).
# Si hay origen: { "kind": "focus_rig", "path": NodePath(...) } o
#                 { "kind": "world_position", "position": Vector3(...) }
func view_transition_origin() -> Dictionary
```

Reglas:
- `HoloTerminalHUDable` devuelve `{"kind": "focus_rig", "path": <FocusedRig>}`
  cuando el terminal tiene `allow_focus_mode` y el rig existe; si no, `{}`.
- El resto de HUDables no sobreescribe el método → `{}` → primera persona.
- **SuitOS no toca la cámara nunca** (regla de integración de FD-296): quien
  activa el rig de foco es `HoloTerminalV2` por su API existente; el modo HUD
  solo le pide "entra en foco" y "sal".

### Momento y duración

- Duración en el rango ya probado de `HelmetHUDV2` (~0.35–0.45 s), configurable
  por export en el presentador.
- La animación corre con el mundo **pausado** (`PAUSE_MODE_PROCESS`), igual que
  en F3.
- Al cerrar, la animación vuelve al mismo origen (inversa exacta).
- Si el HUDable desaparece del mundo durante la transición (escena recambiada),
  la transición se corta al estado final sin dejar el mundo pausado ni cámara
  huérfana.

## Files

- `core_v2/components/HUDableComponent.gd` (additive: `view_transition_origin()`)
- `core_v2/components/HoloTerminalHUDable.gd` (additive: devuelve su FocusedRig)
- `core_v2/ui/hud/HudModeOverlay.gd` (elige el modo de transición)
- `core_v2/things/HoloTerminalV2.gd` — **NO se toca**: se usa su API de foco
  existente (`_enter_focus_mode()` vía la señal/API pública si ya existe; si no,
  se expone un wrapper aditivo en `HoloTerminalHUDable`)
- `docs/features/FD-296_odisea_os.md` (§4: la decisión de transición por origen)

## Verification

1. Abrir el HUD desde una **HoloTerminal** del Módulo Criogenia: la vista viaja
   hacia la **cámara de foco del terminal** (no al casco genérico) y al cerrar
   vuelve al terminal. Sin cortes de cámara ni cursores robados.
2. Abrir el HUD desde una pantalla de **sistema** (`SystemStatusScreen`): la
   vista viaja a **primera persona** durante el modo HUD y vuelve.
3. La animación corre con el mundo pausado (`PAUSE_MODE_PROCESS`) y el segundo
   TAB durante la transición no deja el mundo pausado sin UI.
4. Cambiar de escena a mitad de transición no deja HUD huérfano (mismo patrón
   que `DebugConsoleManager`).
5. Sin regresiones en `HoloTerminalV2` (el modo terminal normal, sin HUD, se
   comporta igual que antes).

## Out of Scope

- Transición 3D en el teléfono (el remoto usa overlay 2D, ver FD-294).
- Cinemáticas de entrada con sonido/voz (backlog).
- Cambiar el rig de foco de los terminales existentes.
