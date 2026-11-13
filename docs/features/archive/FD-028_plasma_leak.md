# FD-028: Plasma Leak Obstacle

**Status:** Superseded
**Priority:** Low
**Effort:** Small
**Created:** 2026-03-02
**Superseded by:** FD-257 (Sistema Plasma), dentro de la familia FD-255

> Este FD describía la fuga de plasma como un obstáculo suelto. Ahora vive como el *fallo* del
> sistema de plasma en `docs/features/FD-257_plasma.md`, con su aviso legible (brillo → zumbido →
> chorro) y su liberación (redirigir el flujo). El contenido de abajo queda como registro.

## Problem

Environmental hazard: plasma leaks that damage/push player.

## Solution

Create `scenes/common/PlasmaLeak.tscn`

- Area-based damage zone
- Visual particle effects
- Push force applied to bodies

## Files to Modify

- `scenes/common/PlasmaLeak.tscn` (new)

## Verification

1. Particles render correctly
2. Player pushed/damaged in zone
3. Deterministic behavior in replay
