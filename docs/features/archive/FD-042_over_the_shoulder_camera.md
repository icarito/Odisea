# FD-042: Over-the-Shoulder Camera

**Status:** Implemented
**Priority:** Medium
**Effort:** Small
**Created:** 2026-05-29
**Completed:** 2026-05-29
**Depends on:** FD-021

## Problem

En espacios estrechos (pasillos de criogenia), la camara 3ra persona centrada
hace que Elias ocupe poco cuadro y la camara roce paredes. Se necesita una
transicion automatica y natural al acercar la camara, con compensacion de
movimiento vertical.

## Solution

Componente `OverTheShoulder.gd` bajo el nodo Logic del PlayerController.
Define una curva especial de zoom: a medida que la distancia efectiva del
SpringArm se acorta, la camara pasa progresivamente de tercera persona centrada
a encuadre over-the-shoulder.

### Comportamiento

1. **Activacion progresiva**: El OTS sigue la misma distancia efectiva del
   zoom. El zoom manual y el acortamiento por colision alimentan la misma curva;
   no hay un segundo modo lateral separado para espacios estrechos.
   La salida de OTS usa `distance_unblend_speed`, mas lenta que la entrada, para
   evitar pops al liberar colision en puertas o esquinas.
   Cuando el brazo colisiona, solo se comprime el offset lateral del hombro
   hacia el centro, manteniendo el zoom para pasar detras del player.
2. **Offset**: side 0.65m, height -0.25m, pivot_z 0.2m, curva ajustable.
3. **Jump compensation integrada al zoom**: Al entrar en el rango OTS, el
   seguimiento vertical lazy del rig se mezcla suavemente hacia follow directo
   del player. La distancia de activacion se configura con
   `ots_camera_follow_start_length` y `ots_camera_follow_full_length`.
4. **Cinematicas**: Se resetea si CinematicManager no esta en modo FREE.

### Arbol de nodos

```
CameraRig/Yaw/Pitch/SpringArm ← offset
Logic/OverTheShoulder ← script
```

## Files Created

- `core_v2/player/OverTheShoulder.gd`

## Files Modified

- `core_v2/actors/Pilot_v2.tscn`
