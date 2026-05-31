# FD-049: Zero-Gravity Camera Rig

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-05-31
**Depends on:** ZeroGravityController, ControllerManager

## Problem

El camera rig actual (Yaw -> Pitch -> SpringArm) asume un "arriba" fijo.
En gravedad cero: SpringArm choca con geometria (jitter), OverTheShoulder
no aplica, pitch limitado a +/-85deg.

## Solution

Dos rigs intercambiables. ControllerManager switchea entre rig de tierra
y ZeroGCameraRig al entrar/salir de ZeroGravityZone.

### ZeroGCameraRig

ZeroGCameraRig (Spatial) -> SpringArm (distancia fija) -> Camera

- Rotacion 6-DOF: yaw + pitch + roll sin limites
- SpringArm sin colision (camara flota a distancia fija)
- OverTheShoulder no actua sobre este rig
- export camera_distance: float = 4.0

### Pitch-Flip (Control Inversion Fix)

Cuando pitch > 90deg o < -90deg, W se invierte. Estilo Descent:

si pitch > 90deg: pitch = 180 - pitch; yaw += 180; roll += 180
si pitch < -90deg: pitch = -180 - pitch; yaw += 180; roll += 180

Aplicar en step_zero_g() despues del mouse delta, antes de orientacion.

### Bug: salir de 0G

Al salir los ejes de la camara quedan desorientados. El rig de tierra
hereda rotacion 6DOF. Fix: reiniciar yaw/pitch al salir, o interpolar
via CinematicManager.

### Animaciones en 0G

Forzar Swim_Idle (flotar) y Jump_Loop (impulsarse). Nunca Walk/Run/Idle.
PilotAnimatorV2 debe recibir parametro is_zero_g.

### ZeroGravityController fixes

- move_dir normalizado
- velocity = lerp(vel, target, accel * dt)
- roll_angle normalizado a +/-PI
- wish_direction restaurado
- Mesh slerp SOLO al avanzar (W). Mesh incluye roll en target.
- show_debug_collision toggle

## Files

Crear: core_v2/camera/ZeroGCameraRig.gd, core_v2/camera/ZeroGCameraRig.tscn
Modificar: core_v2/player/ControllerManager.gd,
          core_v2/player/ZeroGravityController.gd,
          core_v2/props/ZeroGravityZone.gd,
          core_v2/actors/Pilot_v2.tscn

## Verification

1. Entrar a 0G -> camara cambia a ZeroGCameraRig sin saltos
2. Pitch 360 libre sin inversion de controles
3. Roll Q/E visible en camara y mesh al avanzar
4. Mesh rota solo al avanzar (W), no en idle/strafe
5. Animaciones: Swim_Idle y Jump_Loop, no Walk/Run
6. Salir de 0G -> camara vuelve al rig anterior suavemente
7. OverTheShoulder inactivo en 0G
8. Probar con ANNA MCP sin headless, mostrar resultados a Sebastian
