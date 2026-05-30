# FD-043: Dynamic Gas & Fluid Puzzles (Simplified)

**Status:** Design
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-05-30

## Problem

En Odisea Acto I necesitamos entornos gaseosos interactivos: bolsas de CO2
pesado que asfixian, vapor sobrecalentado que bloquea pasajes, fugas de gas
inflamable reactivas a chispas. El spec anterior (Navier-Stokes en GPU) es
inviable para HTML5/WebGL en Godot 3.6. Necesitamos un sistema que corra a
60 FPS en WebGL, interactivo con el jugador y cuerpos rigidos, con asfixia
e inflamabilidad.

## Solution

Particulas Flipbook con Fisica Emulada. Sin solver de fluidos. El gas se
representa con particulas CPU 3D usando MultiMeshInstance y un atlas de
texturas flipbook 8x8 (64 frames de humo).

### Arquitectura

```
GasArea3D (Area)
├── CollisionShape — volumen del area
├── GasGrid (Object) — grilla 32x32 de densidad local
├── Tween — animaciones de fade y escala
└── GasParticleManager
    └── MultiMeshInstance (GLES2 draw call optima)
```

### Fisica Emulada por Particula

Cada particula tiene posicion y velocidad 3D. Por frame:

1. Flotabilidad termica:
   v_p += buoyancy * g_local * dt
   (buoyancy > 0 = cae al suelo, < 0 = sube al techo)

2. Inyeccion por proximidad del jugador:
   Si d < R: v_p += v_body * player_push_force * (1 - d/R) * dt

3. Friccion (viscosidad):
   v_p *= (1.0 - viscosity * dt)

4. Decaimiento:
   Si lifetime > max_lifetime, se desactiva la particula

### Grilla de Densidad 32x32

El plano horizontal del GasArea3D se divide en 32x32 celdas. Cada frame:

- Se indexa cada particula en su celda (X_3d, -Z_3d).
- Si la celda del jugador supera damage_threshold -> asfixia/daño.
- Para gases inflamables: automata celular sobre la grilla.
  - Ignicion: una chispa marca la celda como ESTADO_COMBUSTION.
  - Propagacion: celdas adyacentes con densidad suficiente se
    incendian tras un retardo.
  - Efecto: particulas mutan a frames de fuego, escala via Tween,
    color naranja con BLEND_MODE_ADD.
  - Senal: gas_ignited(position, radius) para empujar cajas y aplicar daño.

### MultiMeshInstance + Flipbook

- MultiMeshInstance con formato 2 (color + custom data).
- Un shader simple en GLES2 avanza el frame del flipbook (uv offset)
  basado en custom_data.x (tiempo de vida normalizado).
- Atlas: 8x8 = 64 frames, textura de humo/gas en blanco/azul/verde.
- Blending: alpha mixture, no add (para acumulacion de gas).

### Sin Viewport Textures

No se usan Viewports. Todo es MultiMeshInstance con material directo.
Esto evita el costo mas alto de rendimiento en HTML5.

### Extends

GasArea3D extiende Area, no InteractableBaseV2 (no es un prop
interactivo, es un volumen de deteccion). El replay se maneja via
restore_snapshot() en GasParticleManager usando el grupo replay_sync.

### Exports del GasArea3D

| Export | Tipo | Default | Descripcion |
|--------|------|---------|-------------|
| gas_type | int (Toxic/Flammable/Steam) | 0 | Tipo de gas |
| viscosity | float | 0.8 | Friccion del gas |
| buoyancy | float | -1.2 | Flotabilidad (+ cae, - sube) |
| decay_rate | float | 0.1 | Velocidad de disipacion |
| is_flammable | bool | false | Gas inflamable? |
| player_push_force | float | 15.0 | Fuerza del jugador al pasar |
| damage_per_second | float | 20.0 | Daño en zona densa |
| grid_resolution | int | 32 | Celdas por lado (16-64) |

## Files to Create

- core_v2/systems/gas/GasArea3D.gd
- core_v2/systems/gas/GasParticleManager.gd
- core_v2/systems/gas/GasArea3D.tscn
- core_v2/systems/gas/shaders/gas_flipbook.shader

## Verification

1. Test de arrastre: instanciar GasArea3D con particulas estaticas.
   Simular cruce del jugador. Verificar que particulas en radio de
   arrastre adquieren velocidad alineada a la trayectoria.

2. Test de combustion: inyectar chispa en celda (0,0) de gas inflamable
   saturado. Verificar que tras 5 frames la combustion avanzo a celdas
   vecinas (0,1) y (1,0).

3. Test de determinismo: ejecutar runtest.sh con dos ejecuciones
   identicas de impulso de gas. Verificar drift = 0.0 en grilla de
   densidad.
