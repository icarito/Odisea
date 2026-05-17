# FD-036: Gravity Manager — World-Rotation Approach

**Status:** In Progress
**Priority:** High
**Effort:** Medium
**Created:** 2026-05-14
**Completed:** -

## Problem

La nave de Odisea usa terrazas dispuestas en espiral alrededor de un eje central (TerraceSpiral). Cada terraza tiene una orientación distinta — su "suelo" apunta radialmente hacia el eje. Sin embargo, el `PlayerControllerV2` asume que "abajo" es siempre `-Y` global (`UP := Vector3.UP`).

**Enfoque incorrecto**: Modificar PlayerController, PlayerJump, cámara y floor detection para up dinámico. Muchos puntos de falla.

**Enfoque correcto**: Rotar el mundo alrededor del jugador en vez de rotar la gravedad. El jugador siempre usa físicas estándar, el entorno se rota para que el "suelo local" de cada terraza apunte a `-Y` global.

## Solution

### Principio

Cada terraza define su **gravity frame** — una transformación que mapea su "abajo local" al `-Y` global. Un `WorldRotator` se coloca como padre del entorno y se rota suavemente para alinear el frame de la terraza actual con el mundo físico del jugador.

```
World
├── PlayerController (sin cambios, UP = Vector3.UP)
│   └── CameraRig (sin cambios)
├── WorldRotator (Spatial)
│   ├── TerraceContainer
│   │   ├── Terrace_0
│   │   └── Terrace_1
│   ├── CentralAxis
│   └── Environment
└── GravityZoneVolumes
```

**Modos:**
| Modo | Comportamiento | Rotación del mundo |
|------|---------------|-------------------|
| 1G estándar | Suelo apunta a -Y | Frame de terraza actual → -Y |
| Centrífuga | Suelo apunta radial al eje | Frame centrífugo → -Y |

### Part 1: GravityWorld Autoload

Centraliza registro de terrazas y calcula target rotation:
- `register_terrace(data: TerraceData)`
- `get_terrace_at(pos) → TerraceData` (por proximidad)
- `get_target_basis(terrace) → Basis` rota `local_down` o `radial_direction` a `Vector3.DOWN`
- `rotate_to_terrace(id, duration)`

### Part 2: WorldRotator.gd

Spatial tool que interpola su basis vía slerp cada frame hacia el target de GravityWorld:
- `rotation_speed: float` (default 2.0 rad/s)
- En `_process()`: `q_current.slerp(q_target, min(1.0, rotation_speed * delta))`

### Part 3: TerraceChunk — Escenas Independientes

Cada terraza es una scene independiente cargada/descargada por distancia:
- Radio carga: 60m
- Radio descarga: 100m
- Fade 0.5s
- TerraceSpiral (MultiMesh) se mantiene como LOD lejano, reemplazado por escenas al acercarse

### Part 4: Transiciones

Al cambiar modo o terraza: WorldRotator slerp al nuevo target. Cámara no afectada. Efecto visual con GravityAnchor/partículas.

## Files to Create

- `core_v2/systems/WorldRotator.gd`
- `core_v2/systems/GravityWorld.gd` + `GravityWorld.tscn`
- `core_v2/systems/TerraceData.gd`
- `core_v2/systems/TerraceRegistry.gd` + `TerraceRegistry.tscn`
- `core_v2/props/TerraceChunk.tscn`
- `tests/test_world_rotation.gd`

## Unmodified Files

PlayerControllerV2, PlayerJumpV2, PlayerMovementV2, camera/ — **sin cambios**

## Verification

1. Modo 1G: terraza sin rotación (comportamiento actual)
2. Modo centrífugo: terraza rotada se ve recta desde el jugador
3. Transición entre terrazas: rotación suave del entorno
4. Player salta y camina sin cambios
5. Scene streaming funciona por distancia
6. `./runtest.sh -a ./core_v2/tests/` pasa completo (regresión cero)