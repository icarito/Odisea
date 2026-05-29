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
Desplaza el SpringArm horizontal/verticalmente cuando se acorta.

### Comportamiento

1. **Activacion progresiva**: Al acortarse el spring arm por debajo de
   distance_max (4.5m), desliza la camara al hombro. A distance_min (1.5m)
   el offset esta al maximo.
2. **Offset**: side 0.65m, height -0.25m, pivot_z 0.2m, curva ajustable.
3. **Jump compensation**: Al saltar, la camara sube 0.4m y retrocede 0.5m.
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
