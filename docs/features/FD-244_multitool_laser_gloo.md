# FD-244: Multi-Tool — Láser + Gloo Gun

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-23

## Problem

El multi-tool es el gadget principal de Elías (se encuentra después del módulo Criogenia). Sirve como navaja suiza para puzzles. Necesita dos modos funcionales jugables: **láser de corte** y **gloo gun** (proyectiles adhesivos). No hay implementación actual.

## Solution

Crear `MultiToolV2.gd` como nodo equipable del jugador, con dos modos intercambiables. Sin interacción con escenas/objetos aún (eso va en FDs de puzzle específicos) — solo la herramienta funcional.

### Modo Láser
- Raycast continuo desde la posición del multi-tool hacia forward del jugador
- Efecto visual: rayo láser color rojo/anaranjado (trail o line2D 3D)
- Efecto de impacto: partículas en punto de colisión
- Sin daño a enemigos ni interacción con puzzles aún — solo el haz funcional
- Input: mantener click izquierdo, el rayo sigue la mirada

### Modo Gloo Gun
- Proyectil esférico que se adhiere a superficies
- Física: gravedad leve, rebote mínimo, se pega al impactar contra StaticBody
- Visual: bola azul/verdosa con glow, partículas al impactar
- Límite: máximo N proyectiles activos (ej: 6), el más viejo se desvanece
- Input: click derecho dispara, recarga automática

### Intercambio de modo
- Rueda del mouse o tecla Q/TAB cambia entre láser y gloo
- UI: indicador de modo activo + count de proyectiles gloo
- Animación: el multi-tool se transforma visualmente (cambia de mesh/color)

### Arquitectura
- `MultiToolV2` es un Spatial hijo de la cámara (o del player root)
- No bloquea movimiento ni interacción
- Totalmente independiente de otros sistemas — puede integrarse después con puzzles

### Considered Options

- **Option A**: Crear desde cero como escena independiente — **Selected**. Sin dependencias de otros sistemas. Se conecta después con puzzles vía signals.
- **Option B**: Integrar en PlayerControllerV2 — descartado, acopla tool con movimiento.

## Files to Modify

- `core_v2/player/MultiToolV2.gd` (nuevo) — controlador principal
- `core_v2/player/MultiToolV2.tscn` (nuevo)
- `core_v2/player/MultiToolLaser.tscn` (nuevo) — visual del láser
- `core_v2/player/MultiToolGloo.tscn` (nuevo) — proyectil gloo
- `core_v2/player/MultiToolGlooProjectile.gd` (nuevo) — física del proyectil
- `core_v2/player/MultiToolModeIndicator.gd` (nuevo) — UI de modo activo
- `core_v2/player/PlayerControllerV2.gd` (modificar) — equipar/desequipar multi-tool
- `core_v2/tests/test_multitool_laser.gd` (nuevo)
- `core_v2/tests/test_multitool_gloo.gd` (nuevo)

## Verification

1. Láser: rayo visible apunta al crosshair, colisiona con StaticBody
2. Gloo: proyectil se dispara, vuela con física, se adhiere a superficie
3. Máximo N proyectiles, el más viejo se elimina
4. Cambio de modo con Q/TAB o rueda del mouse
5. UI muestra modo activo y count de gloo
6. No interfiere con movimiento, salto, interacción
7. Deterministic replay compatible (el láser no modifica el mundo, gloo proyectiles se snapshot)
