# FD-045: Retractable Bridge B-4

**Status:** Design
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-05-29
**Depends on:** SlidingObjectV2, RotatingObjectV2

## Problem

El modulo Criogenia necesita un puente que solo se extiende al activar energia
auxiliar. Sin energia, el puente esta retraido y el jugador no puede cruzar.
Con energia, se despliega.

## Solution

Puente compuesto por dos brazos mecanicos rotatorios que despliegan una
seccion de piso. Reutilizar componentes existentes:

- RotatingObjectV2 para los brazos (rotan 90 grados)
- SlidingObjectV2 para la plataforma (se desliza horizontalmente)

### Comportamiento

1. Estado inicial (sin energia): brazos plegados contra la pared, plataforma
   retraida. Visible desde Sala B.
2. Al recibir senal "energy_on" desde el Lever: brazos rotan 90 grados,
   plataforma se desliza hacia afuera.
3. Una vez extendido: el jugador puede cruzar.
4. La plataforma usa SteelGratePlatform o ScaffoldWalkway como superficie.

### Arbol de nodos

```
RetractableBridge (Spatial)
├── LeftArm (RotatingObjectV2) — rota en Y
├── RightArm (RotatingObjectV2) — rota en Y
├── Platform (SlidingObjectV2) — se desliza en Z
│   └── ScaffoldWalkway (MeshInstance) — superficie
├── SignalReceiver (Node) — escucha senal energy_on
│   conectado al lever_v2.lever_toggled
```

### Exports

| Export | Tipo | Default | Descripcion |
|--------|------|---------|-------------|
| extend_time | float | 2.0 | Duracion de la animacion de despliegue |
| platform_length | float | 4.0 | Largo de la plataforma extendida |

## Files to Create

- `core_v2/props/RetractableBridge.tscn`

## Files to Reuse

- `core_v2/components/RotatingObjectV2.gd`
- `core_v2/components/SlidingObjectV2.gd`
- `core_v2/props/scaffold/ScaffoldWalkway.tscn`
- `core_v2/props/scaffold/SteelGratePlatform.tscn`

## Verification

1. Puente retraido visible desde Sala B antes de energia.
2. Al accionar Lever, brazos rotan y plataforma se extiende.
3. Player cruza el puente.
4. Puente no se puede cruzar sin energia.
