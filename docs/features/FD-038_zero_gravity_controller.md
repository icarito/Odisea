# FD-038: ZeroGravityController & Controller Swapping

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-05-17
**Depends on:** InputDataV2, InputProviderV2, replay_sync group, snapshot system
**Supersedes:** player/PlayerControllerV2.gd (no lo reemplaza — conviven)

## Problem

El Acto I necesita secciones de **gravedad cero** (cuerpo central de la nave, exterior, módulos sin rotación). El PlayerControllerV2 actual asume gravedad hacia -Y, snap al suelo, salto Coyote Time, crouch físico — todo esto no aplica en 0G.

**No se puede** modificar PlayerControllerV2 para que haga ambas cosas porque:
- Las físicas de 0G son fundamentalmente distintas (inercia, 6DOF, drift)
- Condicionales `if zero_g_mode` rompen legibilidad y determinismo
- Crouch en 0G = moverse hacia abajo, no reducir collider
- Necesita rotación Q/E que en 1G no existe

**Solución:** Segundo controlador (`ZeroGravityController`) intercambiable mediante **ControllerManager**. Ambos consumen `InputDataV2` y se integran con `replay_sync`.

## Arquitectura

```
Scene
└── PlayerRoot (Spatial)
    ├── CollisionShape
    ├── CameraRig (compartida)
    ├── ControllerManager
    │   ├── switch_to(mode)
    │   └── current_controller: Node
    ├── PlayerControllerV2 (desactivado cuando no es current)
    └── ZeroGravityController (desactivado cuando no es current)
```

ControllerManager desactiva process del saliente, activa el entrante, transfiere transform, emite `controller_changed(mode)`.

## ZeroGravityController — Controles

| Input | Acción |
|-------|--------|
| WASD | Lateral relativo a cámara |
| Space | Ascender (+Y local) |
| C | Descender (-Y local) |
| Shift | Boost 2x |
| Mouse | Yaw + pitch |
| Q | Yaw left (snap 90° o continuo) |
| E | Yaw right |

### Físicas

Sin gravedad. Inercia con fricción:
- `base_speed: 8.0`, `vertical_speed: 5.0`, `acceleration: 15.0`, `friction: 0.95`
- Move direction desde camera basis (forward/right/up)
- `velocity.linear_interpolate(target, accel * dt)` + `*= friction` sin input

### Rotación Q/E — Opciones
A) Snap 90° (recomendado) | B) Continua | C) Tap = snap, hold = continuo

### Cámara, Collider, Replay

- Mismo CameraRig. Sin auto-align.
- CapsuleShape igual. Crouch no reduce collider.
- Snapshot: `{ pos, vel, yaw, pitch }`

### Transición 1G ⇄ 0G

1. ControllerManager.switch_to(mode)
2. Transferir posición + rotación
3. Soltar crouch legacy
4. Conservar `velocity.length()` como base
5. Efectos visuales opcionales

## InputMap — Acciones Nuevas

| Acción | Tecla |
|--------|-------|
| `rotate_left` | Q |
| `rotate_right` | E |

E es `interact` actualmente. En 0G la prioridad cambia.

## Files to Create

- `core_v2/player/ZeroGravityController.gd`
- `core_v2/player/ControllerManager.gd`

## Files to Modify

- `project.godot` — acciones rotate_left, rotate_right
- `PlayerControllerV2.gd` — exponer transform/velocity
- `replay_sync` — incluir controller_mode

## Files NOT Modified

`InputDataV2.gd`, `InputProviderV2.gd`, `PlayerJumpV2.gd`, `PlayerMovementV2.gd`

## Verification

1. WASD mueve relativo a cámara
2. Space = subir, C = bajar
3. Q/E rotan 90°
4. Fricción frena gradualmente
5. Sprint = 2x
6. Swapping mantiene posición
7. Replay determinista con cambios de modo
8. `./runtest.sh -a ./core_v2/tests/` pasa completo