# FD-049: Zero-Gravity Camera Rig

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-05-31
**Depends on:** ZeroGravityController, ControllerManager

## Problem

El camera rig actual (Yaw → Pitch → SpringArm) asume un "arriba" fijo.
En gravedad cero: el SpringArm choca con geometria (jitter), OverTheShoulder
no aplica, el pitch esta limitado a ±85°, y las animaciones terrestres
(Walk, Run, Idle) rompen la ilusion de 0G.

## Solution

Dos rigs intercambiables. ControllerManager switchea entre el rig de tierra
y el de 0G al entrar/salir de ZeroGravityZone.

### ZeroGCameraRig

ZeroGCameraRig (Spatial) → SpringArm (distancia fija) → Camera

- Rotacion 6-DOF: yaw + pitch + roll sin limites
- SpringArm sin colision (camara flota a distancia fija)
- OverTheShoulder no actua sobre este rig
- export camera_distance: float = 4.0

### Integracion con ControllerManager

Al activar zero_gravity: guarda rig anterior, desactiva CameraRig (visible=false,
camera.current=false), activa ZeroGCameraRig. Al salir: inverso.
Transicion via CinematicManager para evitar saltos.

ZeroGravityZone debe notificar a ControllerManager al entrar/salir.

### Pitch-Flip (Control Inversion Fix)

Cuando pitch > 90° o < -90°, W se invierte. Solucion estilo Descent:

```
si pitch > 90°:
  pitch = 180° - pitch
  yaw += 180°
  roll += 180°
si pitch < -90°:
  pitch = -180° - pitch
  yaw += 180°
  roll += 180°
```

Aplicar en step_zero_g() despues del mouse delta, antes de aplicar
orientacion al rig. W siempre es "adelante".

### Bug: salir de 0G

Al salir los ejes de la camara quedan desorientados. El rig de tierra
hereda rotacion 6DOF sin reiniciar. Fix: reiniciar yaw/pitch al salir,
o interpolar via CinematicManager.

### Animaciones en 0G

Forzar Swim_Idle (flotar) y Jump_Loop (impulsarse). NUNCA Walk, Run, Idle.
PilotAnimatorV2 debe recibir parametro is_zero_g.

### ZeroGravityController fixes

- move_dir normalizado
- velocity = lerp(vel, target, accel * dt)
- roll_angle normalizado a ±PI
- wish_direction restaurado
- Mesh slerp SOLO al avanzar (W). Mesh incluye roll en target.
- show_debug_collision toggle

### Instrucciones para Codex

- Probar con ANNA MCP sin headless para ver resultados visuales.
- Mostrar a Sebastian los cambios antes de mergear.
- NO asumir que ControllerManager ya switchea rigs - implementarlo.

## Files

Crear: core_v2/camera/ZeroGCameraRig.gd, core_v2/camera/ZeroGCameraRig.tscn
Modificar: core_v2/player/ControllerManager.gd,
          core_v2/player/ZeroGravityController.gd,
          core_v2/props/ZeroGravityZone.gd,
          core_v2/actors/Pilot_v2.tscn (agregar ZeroGCameraRig)

## Verification

1. Entrar a 0G → camara cambia a ZeroGCameraRig sin saltos
2. Pitch 360° libre sin inversion de controles
3. Roll Q/E visible en camara y mesh al avanzar
4. Mesh rota solo al avanzar (W), no en idle/strafe
5. Animaciones: Swim_Idle y Jump_Loop, no Walk/Run
6. Salir de 0G → camara vuelve al rig anterior suavemente
7. OverTheShoulder inactivo en 0G
