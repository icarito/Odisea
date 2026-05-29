# FD-041: Faux Skydome / Terrace Segmentation & LOD

**Status:** Design (Revision 2)
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-05-23
**Updated:** 2026-05-29
**Depends on:** FD-036, FD-039, WorldRotator, PlateContentStream

## Problem

Odisea necesita vender escala, nave y rotacion centrifuga de las terrazas sin
pagar el costo de draw calls del WorldRotator completo. En HTML5/WebGL el
rendimiento es abismal por acumulacion de geometria, luces y GDScript.

Solucion: segmentar la espiral en N arcos (12 segmentos de 30 grados) y
asignar LOD por segmento segun distancia al jugador y plates activos.

## Solution

### Arquitectura

```
WorldRotator
+-- TerraceSpiral
+-- FauxSkydomeParallaxShell (LOD0 global)
+-- TerraceSegmentManager
    +-- Segment_00 (LOD1 / LOD2)
    +-- Segment_01
    +-- ...
    +-- Segment_11
```

### LOD por segmento

| LOD | Tecnica | Draw calls | Colision | GPU |
|-----|---------|------------|----------|-----|
| 0 | FauxSkydome (cilindro texturizado) | 1 | No | Bajo |
| 1 | MultiMeshInstance con bake | 1 | No | Bajo |
| 2 | MeshInstance individual | 1/segmento | Si | Medio |

### Reglas

- LOD0 siempre visible.
- LOD1 visible donde LOD2 no esta activo.
- LOD2 activo solo para: segmento del player, 2 vecinos, segmentos con
  PlateContentStream activo.
- HTML5: solo LOD0 + LOD1.

### Integracion PlateContentStream

PlateContentStream.loaded_plates -> TerraceSegmentManager
  -> segment = plate.spiral_index / 12
  -> promocionar a LOD2

### FauxSkydomeParallaxShell (LOD0)

Cilindro/esfera invertida, 3 capas:
- HullDepthLayer: casco interior de nave
- IndustrialGridLayer: textura baked de la espiral
- WarningLightLayer: Sprites de luces

## Files to Create

- core_v2/systems/visual/TerraceSegmentManager.gd
- core_v2/systems/visual/FauxSkydomeParallaxShell.gd
- shaders/faux_skydome_parallax.shader

## Files to Modify

- core_v2/systems/WorldRotator.gd
- core_v2/systems/PlateContentStream.gd

## Verification

1. Segmentos visibles sin gaps.
2. LOD0 en distancia, LOD1 al acercarse, LOD2 al llegar.
3. HTML5 mantiene 30+ FPS con LOD0+LOD1.
4. PlateContentStream promociona/degrada segmentos.
5. Sin popping visual al cambiar LOD.
