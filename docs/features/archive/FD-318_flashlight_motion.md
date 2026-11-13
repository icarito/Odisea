# FD-318: Linterna de casco — movimiento propio (inercia + sway)

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-09-25
**Parent:** FD-280 (linterna de casco)

## Problem

La linterna de casco (`HelmetFlashlight`) montada en el hombro apunta casi 1:1 a la
cámara: `_resolve_aim()` sigue la dirección de cámara y `_aim_smoothed` la persigue
con `aim_lerp_speed = 9.0` (un `1 - exp(-9·dt)` que converge en ~0.1 s). Resultado:
el haz se siente "pegado a la cara" — un láser rígido, sin inercia y sin reacción al
cuerpo. Cuando Elías corre o salta, la luz no se mueve salvo por la rotación de
cámara; cuando la cámara gira, la luz la sigue de forma exacta e instantánea. Falta la
sensación de que la luz es un objeto físico que Elías lleva encima y que *persigue* a
la cámara en vez de estar soldado a ella.

Sebastián quiere:
1. El haz se mueva de acuerdo al movimiento de Elías (correr, saltar, girar).
2. Al mover la cámara, la linterna la siga de forma *natural* (lag + inercia), no
   exacta — por momentos el haz no queda 100% centrado y se "despega" del centro de la
   vista.

## Solution

Tres mecanismos **aditivos** sobre el apunte actual, sin tocar la geometría de montaje
(el origen sigue en el hombro `DEF-upper_armR`):

### 1. Inercia de apunte (spring de 2º orden)

Reemplazar el lerp exponencial de primer orden por un **spring de segundo orden**
(posición angular + velocidad angular) que introduzca lag real y un leve *overshoot*
al girar. La luz persigue la dirección objetivo pero "se pasa" un poco y se asienta,
en vez de converger de golpe.

- Mantener `_resolve_aim()` (clamp de 75° respecto del cuerpo) como generador del
  objetivo angular.
- Convertir el objetivo y el apunte suavizado a **yaw/pitch relativos al frente del
  cuerpo** (`body_forward`), aplicar el spring por eje, y reconstruir la dirección.
- Defaults: stiffness (frecuencia natural) ~ 12–18 rad/s, damping ratio ~ 0.5–0.7
  (levemente subamortiguado para el overshoot). Exponer como `export` tuneable.
- Estado nuevo: `_aim_yaw/_aim_pitch` + `_aim_yaw_vel/_aim_pitch_vel`. Se resetean
  junto a `_aim_initialized` (ver Determinismo).

### 2. Sway / bob procedimental

Offset aditivo (yaw/pitch) aplicado **después** del spring y **antes** del clamp de
`aim_limit_deg`, alimentado por el estado del cuerpo:

- **Sway lateral (yaw)** ∝ aceleración lateral del cuerpo: derivada de la componente
  horizontal de `velocity` proyectada sobre el eje lateral del cuerpo. El haz se
  inclina al iniciar un giro o un strafe y vuelve al centro al estabilizarse.
- **Pitch de salto** ∝ `velocity.y` + transición airborne→grounded: leve subida al
  ascender, dip al aterrizar. Acoplado a `is_effectively_grounded()` y `velocity.y`.
- **Bob (opcional)** por fase acumulada ∝ distancia recorrida (periódico en
  `horizontal_speed`, no en reloj de pared).

### 3. Rotación acoplada al cuerpo en maniobras (backflip)

Durante el backflip Elías rota el cuerpo completo (animación `Backflip001` vía
AnimationTree, con `PilotAnimatorV2.is_rotation_locked` congelando el yaw del pivot),
pero la linterna deriva su apunte de la cámara y no del cuerpo: el haz queda "pegado a
la cámara" mientras el cuerpo gira debajo. El haz debe **rotar con el cuerpo** a lo
largo del flip.

- **Fuente de estado:** suscribirse a `controller.acrobatic_jumped` (señal de
  `PlayerControllerV2`, línea 235/2801) para armar un latch `_acrobatic_active = true`;
  limpiarlo al aterrizar (`controller.is_effectively_grounded()`). El controller es
  `get_parent()` (KinematicBody con `PlayerControllerV2.gd`), que ya expone la señal.
- **Frame de referencia del cuerpo:** mientras `_acrobatic_active`, el `body_forward` de
  `_resolve_aim()` se deriva del **basis global del hueso de montura**
  (`_skeleton.get_bone_global_pose(_mount_bone_idx).basis`, misma convención +Z que el
  origen, que ya rota con el flip) en vez del basis del pivot (que queda congelado). El
  cono de clamp (75°) rota entonces con el cuerpo y el haz barre con el flip; al
  aterrizar vuelve al seguimiento de cámara normal.
- **Determinismo:** la señal + el estado grounded + la pose del hueso son todos
  replay-deterministas (mismo estado reproducible).

Amplitudes/frecuencias/stiffness como `export` con defaults **conservadores** (que se
sientan pero no marean), tuneables en editor. Los valores finales se validan en
playtest con Sebastián.

### Considered Options

- **Lerp de primer orden más lento (solo bajar `aim_lerp_speed`)** — barato, pero sin
  overshoot ni sensación de masa; sigue sin reaccionar al cuerpo. Descartado como
  solución completa.
- **Spring 2º orden + sway procedimental** — lag + overshoot + reacción al movimiento,
  todo aditivo y determinista. Seleccionado.
- **PhysicsBone / rigidbody para la lámpara** — realista pero caro y no determinista.
  Descartado (Core V2).

## Determinismo (Core V2)

Todo el movimiento se alimenta de:
- `velocity` y `is_effectively_grounded()` del controller (ya deterministas).
- Un acumulador de fase que avanza con `delta` de `_physics_process` (dt fijo).

**Prohibido:** `OS.get_ticks_*`, `randf()`, `rand_range()`, o cualquier fuente no
determinista. El estado del spring y la fase se resetean en `set_enabled()` (igual que
`_aim_initialized` hoy) y en cualquier teleport/respawn que ya resetee la linterna,
para que el replay reproduzca el mismo apunte frame a frame.

## Files to Modify

- `core_v2/props/lights/HelmetFlashlight.gd` (modify): spring 2º orden + sway/bob.
- `core_v2/props/lights/HelmetFlashlight.tscn` (modify): espejar defaults nuevos si se
  exponen en la escena.

### Cómo obtiene el estado del cuerpo

La linterna es hija directa de `Pilot` (KinematicBody con `PlayerControllerV2.gd`).
`get_parent()` devuelve el controller, que expone `velocity`, `is_effectively_grounded()`
y `is_on_floor()`. La cámara se obtiene como hoy: `get_viewport().get_camera()`.

## Verification

1. Encender la linterna y **girar la cámara rápido**: el haz laggea y hace un leve
   overshoot antes de asentarse; por momentos no queda centrado en la vista.
2. **Correr** con Elías: el haz hace sway lateral perceptible y vuelve al centro al
   frenar.
3. **Saltar**: leve pitch al ascender y dip al aterrizar.
4. **Replay determinista**: reproducir un segmento con la linterna encendida dos veces;
   el apunte debe ser idéntico frame a frame.
5. **Backflip:** el haz rota con el cuerpo a lo largo del flip (no queda apuntando a la
   cámara) y recupera el seguimiento normal al aterrizar.
6. Correr los tests existentes de la linterna (`core_v2/tests/test_helmet_flashlight.gd`,
   `test_flashlight_screen.gd`) — deben seguir verdes.
7. Sin linterna encendida: comportamiento inalterado (no consume CPU extra).

## Out of scope

- Cambiar el montaje/geometría (hombro, cono, máscara) — solo apunte.
- Persistencia o cambios en el flujo de muerte/respawn.
- Ajustar `MobileLightBudget` o el budget de luces.
