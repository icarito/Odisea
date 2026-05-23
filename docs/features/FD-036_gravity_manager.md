# FD-036: Gravity Manager — World-Rotation Approach

**Status:** Implemented / In Progress
**Priority:** High
**Effort:** Medium
**Created:** 2026-05-14
**Completed:** -

**Engineering contract:** `docs/engineering/Gravity_Physics_Contracts.md`

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

**Modos actuales:**
| Modo | Comportamiento | Rotación del mundo |
|------|---------------|-------------------|
| `STANDARD_1G` | Gravedad global hacia `-Y` | Sin frame centrífugo |
| `SPIN_WALKABLE` | Player usa física estándar; gravedad canónica puede apuntar radialmente hacia afuera del eje | `WorldRotator` alinea la placa seleccionada con el frame caminable |
| `ZERO_G` | Controlador separado sin gravedad | Sin asumir suelo |
| `SPIN_DYNAMIC` | Props opt-in reciben pseudo-gravedad radial | No reemplaza el sistema caminable |

`GravityWorld.gravity_blend` permite mezclar `STANDARD_1G` y radial
centrífugo. Esto representa terrazas o fallas donde la fuerza se lee diagonal,
por ejemplo una placa visualmente a 45 grados con gravedad inclinada entre
radial y `-Y`. La orientación de la placa y la dirección real de gravedad pueden
divergir en trabajos futuros por razones narrativas.

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

### Part 3: PlateContentStream — Contenido de Gameplay

La revisión FD-039 reemplazó la idea de meter contenido con física dentro de
`WorldRotator`. En Godot 3 eso teletransporta colisiones al rotar el padre.

Contrato vigente:

- `WorldRotator` contiene visuales, `TerraceSpiral`, skybox y staging visual.
- Gameplay con física debe ir fuera de `WorldRotator`.
- `PlateContentStream` materializa sub-escenas en slots globales cuyo transform
  se calcula desde `WorldRotator.global_transform * plate_canonical_transform`.
- `BaseTerrace` todavía es híbrida/legacy y mantiene
  `centrifugal_current_plate_only_physics = false` hasta migrar su física a
  slots.

### Part 4: TerraceChunk — Escenas Independientes

Cada terraza es una scene independiente cargada/descargada por distancia:
- Radio carga: 60m
- Radio descarga: 100m
- Fade 0.5s
- TerraceSpiral (MultiMesh) se mantiene como LOD lejano, reemplazado por escenas al acercarse

### Part 5: Transiciones

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

## Estado 2026-05-23

- `BaseTerrace` funciona en modo centrífugo con `WorldRotator`.
- `WorldRotator` es `tool`, pero no debe mutar transforms en `Engine.editor_hint`.
- La terraza puede verse inclinada en runtime por el frame centrífugo, pero el
  editor no debe reescribir esa pose por side effects de `_ready()`.
- El ventilador / fan visual que existía en el contexto de `WorldRotator` quedó
  fuera del pase actual; reintroducirlo es secundario y debe hacerse sin añadir
  física global costosa.

## Verification

1. Modo 1G: terraza sin rotación (comportamiento actual)
2. Modo centrífugo: terraza rotada se ve recta desde el jugador
3. Transición entre terrazas: rotación suave del entorno
4. Player salta y camina sin cambios
5. Scene streaming funciona por distancia
6. `./runtest.sh -a ./core_v2/tests/` pasa completo (regresión cero)
