# FD-044: Pipe Valve & Conduit Props

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-05-29

## Problem

El modulo Criogenia necesita tuberias rotas y valvulas interactivas para
soportar la narrativa de sabotaje y las mecanicas de reparacion. Actualmente
no hay props de tuberias ni valvulas en el inventory.

## Solution

### PipeValve (Interactivo)

Valvula de volante (tipo rueda) montada en una seccion de tuberia. El jugador
interactua con ella para abrir/cerrar el paso de gas o fluido.

- Extiende InteractableBaseV2
- Animacion de rotacion del volante (eje Z, ~180 grados)
- Emite senal al cambiar de estado (valve_opened, valve_closed)
- Se puede conectar a LeakEmitter o PedestalButton logic.

### PipeSection / PipeCorner (Decorativos)

Geometria simple de tuberia industrial para ambientar pasillos y salas.

- PipeSection: tuberia recta (2m, 4m)
- PipeCorner: codo 90 grados
- PipeTee: interseccion en T
- Material metalico con emission sutil para bordes
- Se pueden agrupar con RadialScatter para redes de tuberias

## Files to Create

- core_v2/props/PipeValve.tscn
- core_v2/props/PipeValve.gd
- core_v2/props/pipe/PipeSection.tscn
- core_v2/props/pipe/PipeCorner.tscn
- core_v2/props/pipe/PipeTee.tscn

## Verification

1. PipeValve se coloca en escena y se interactua (rueda gira)
2. Conectar PipeValve a LeakEmitter — al cerrar valvula, fuga se detiene
3. Tuberias decorativas se alinean correctamente en esquinas y pasillos
