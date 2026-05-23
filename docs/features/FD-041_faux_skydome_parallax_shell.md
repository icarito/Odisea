# FD-041: Faux Skydome / Centrifugal Parallax Shell

**Status:** Design
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-05-23
**Completed:** -
**Depends on:** FD-036, FD-039

**Engineering contract:** `docs/engineering/Gravity_Physics_Contracts.md`

## Problem

Odisea necesita vender escala, nave y rotacion centrifuga alrededor de las
terrazas sin pagar inmediatamente el costo del `InfiniteScaffoldField` completo.
El scaffold procedural sigue siendo prometedor, pero hoy esta bloqueado por
presupuesto de nodos/draw calls, reciclaje amortizado y exclusiones authorables.

Para poder construir niveles ya, se necesita una capa visual barata que sugiera:

- casco o volumen interior de nave;
- estrellas/exterior visible a traves de aperturas o ventanales;
- la espiral como landmark lejano;
- profundidad entre plates, espiral y estructura lejana;
- movimiento relativo durante cambios de frame centrifugo;
- continuidad entre interiores cerrados y zonas abiertas de espiral.

Esta capa no debe introducir gameplay, colisiones ni dependencia de fisica.

## Solution

Crear un `FauxSkydomeParallaxShell` visual bajo `WorldRotator`, usado como LOD
lejano o sustituto temporal del scaffold:

```text
WorldRotator
+-- TerraceSpiralVisual
+-- FauxSkydomeParallaxShell
    +-- HullDepthLayer
    +-- IndustrialGridLayer
    +-- WarningLightLayer
```

La primera version debe favorecer materiales, texturas y `MultiMesh` muy barato
antes que geometria detallada:

- shell cilindrico o esferico invertido, centrado en el eje de nave;
- 2-3 capas con parallax sutil basado en camara/canonico;
- textura industrial repetible o baked atlas de tuberias/soportes;
- scrolling lento opcional para vender rotacion o profundidad;
- sin colision;
- sin luces dinamicas necesarias;
- switch `enabled_on_low_profile` / `quality_level`.

### Runtime Contract

- Vive bajo `WorldRotator` porque es visual y debe compartir el frame
  centrifugo.
- Sus decisiones de posicion/parallax deben usar espacio canonico cuando sea
  necesario, no el origen local de un chunk arbitrario.
- Nunca bloquea `PlateContentStream`, transiciones, colisiones o replay.
- Puede actualizarse en `_process()` porque es visual-only, pero debe exponer un
  metodo determinista `force_update(canonical_camera_pos)` para tests o capturas.

### Visual Direction

El resultado debe poder alternar entre dos lecturas compatibles: casco/exterior
espacial y estructura interna de espiral. No debe sentirse como un cielo natural
generico:

- capas oscuras de casco, estrellas contenidas, grids tecnicos, tuberias lejanas
  y luces discretas;
- silueta reconocible de la espiral cuando el punto de vista lo permita;
- contraste suficiente para mostrar rotacion sin competir con plataformas;
- sin miles de piezas individuales lejanas;
- evitar movimiento rapido de fondo que cause mareo.

### Relationship to FD-037

Si funciona, este shell se convierte en el LOD lejano de `InfiniteScaffoldField`.
Si no funciona, se elimina sin afectar gameplay porque no tiene estado fisico ni
contratos de nivel.

## Considered Options

- **Option A: Integrar ya el scaffold infinito completo**: mayor fidelidad, pero
  alto riesgo de rendimiento y authoring antes del slice jugable.
- **Option B: Fondo estatico simple**: barato, pero no ayuda a vender rotacion ni
  profundidad.
- **Option C: Shell visual con parallax por capas**: barato, reversible y puede
  evolucionar a LOD lejano de FD-037.
- **Selected:** Option C.

## Files to Create

- `core_v2/systems/visual/FauxSkydomeParallaxShell.gd`
- `core_v2/systems/visual/FauxSkydomeParallaxShell.tscn`
- `shaders/faux_skydome_parallax.shader`
- `core_v2/tests/visual/test_faux_skydome_parallax.oys`

## Files to Modify

- `docs/features/FEATURE_INDEX.md`
- Escenas de prueba bajo `core_v2/levels/` o `core_v2/tests/` que necesiten
  validar el fondo centrifugo.

## Verification

1. Activar el shell bajo `WorldRotator` y confirmar que rota coherentemente con
   el frame centrifugo.
2. Cruzar una transicion interior -> espiral y verificar que el fondo aparece
   sin stutter visible.
3. Capturar un recorrido corto y confirmar que el parallax no produce mareo ni
   popping.
4. Comparar draw calls y FPS contra una escena con scaffold lejano prototipo.
5. Confirmar que desactivar el shell no cambia colisiones, replay ni gameplay.
