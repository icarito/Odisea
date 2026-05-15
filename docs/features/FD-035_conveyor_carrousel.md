# FD-035: ConveyorCarrousel & Conveyor Enhancements

**Status:** Design
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-05-12
**Completed:** -

## Problem

El conveyor lineal actual empuja siempre que está activo, sin considerar si hay algo encima. No hay feedback visual de estado. Para el nivel del Acto I (Criogenia) y puzzles de carga, se necesita:

1. Un **conveyor circular** (carrousel) que lleve objetos/player en trayectoria radial
2. **Ocupancy detection** — el conveyor solo funciona cuando detecta un cuerpo encima
3. **Indicator lights** — feedback visual del estado (active/idle/disabled)
4. **Metal plates** — cubiertas decorativas en entradas, salidas y costados
5. **Solid base** — base física debajo de la cinta

## Solution

### Part 1: Occupancy Detection + Indicator Lights (Conveyor.gd)

Añadir al `Conveyor.gd` existente:

- `occupancy_detection: bool` — si true, el conveyor solo aplica fuerza cuando hay bodies overlapping
- `debounce_time: float` — pequeño retardo (0.2s) antes de desactivarse para evitar flickering
- `idle_speed_ratio: float` — velocidad de la animación en idle (10% de la velocidad activa, solo visual)
- Indicator lights: 3 x `OmniLight` + 3 x `MeshInstance` (cilindros/paneles) con colores (lógica industrial):
  - **Verde**: ready — conveyor listo para trabajar (idle, con power, esperando carga)
  - **Amarillo**: running — conveyor funcionando (activo, moviendo carga)
  - **Rojo**: disabled/blocked — conveyor desactivado o trabado (sin power o bloqueo)
- Luces son hijos directos del Conveyor, posicionadas en un extremo
- **Ancho por defecto**: cambiar de 2.0 a 3.0 (1.5x más ancho)

### Part 2: ConveyorCarrousel (nuevo)

Nuevo componente `ConveyorCarrousel.gd` que extiende el patrón de Conveyor pero con movimiento circular:

- `radius: float` — radio del carrousel (default 3.0)
- `angular_speed: float` — velocidad angular en rad/s (default 1.0)
- En vez de empujar en `basis.x`, calcula la dirección tangente en la posición de cada body relativa al centro
- El push direction = cross(up, radial_dir) * angular_speed * radius
- Visual: mesh circular (torus sector o cilindro segmentado) con shader de rayas radiales
- Guardrails circulares alrededor
- Misma occupancy detection y luces que el Conveyor mejorado

### Part 3: Metal Plates & Solid Base

- **Metal plates**: MeshInstance hijos en posiciones fijas del conveyor (entrada/salida, costados)
  - Pueden ser CSGBox o MeshInstance con material metálico
  - Se escalan con length/width del conveyor
- **Solid base**: StaticBody + CollisionShape debajo del belt (ya existe `Ground` parcialmente, se refuerza)
  - Se añade un visual (CSGBox o MeshInstance) para la base sólida metálica

### Considered Options

- **Option A (selected)**: Modificar Conveyor.gd existente + nuevo ConveyorCarrousel.gd
  - Pros: Reusa shader, sistema de snapshot, patrón de replay
  - Cons: Carrousel comparte lógica pero es script separado
- **Option B**: Herencia con clase base ConveyorBase
  - Pros: DRY máximo
  - Cons: Más refactor, riesgo de romper escenas existentes
- **Option C**: Todo en un solo script con mode linear/circular
  - Pros: Un solo archivo
  - Cons: Complejidad condicional, viola Single Responsibility

## Files to Modify

- `core_v2/components/Conveyor.gd` (modify — add occupancy, lights, base, plates)
- `core_v2/props/Conveyor.tscn` (modify — add light nodes, plate meshes, base visual)

## Files to Create

- `core_v2/components/ConveyorCarrousel.gd` (new — circular conveyor logic)
- `core_v2/props/ConveyorCarrousel.tscn` (new — carrousel scene with meshes)
- `shaders/conveyor_carrousel_stripes.shader` (new — radial stripe shader)
- `docs/features/FD-035_conveyor_carrousel.md` (this file)

## Verification

1. Conveyor existente carga sin errores en escena existente
2. Occupancy detection: conveyor idle sin bodies, activo con bodies encima
3. Luces cambian de color según estado
4. ConveyorCarrousel empuja bodies en trayectoria circular
5. Carrousel + Conveyor pasan test de determinismo
6. Metal plates y base se escalan correctamente con length/width
7. `./runtest.sh -a ./core_v2/tests/` pasa completo