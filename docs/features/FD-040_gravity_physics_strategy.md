# FD-040: Gravity Physics Strategy for Godot 3

**Status:** Revised
**Priority:** High
**Effort:** Medium
**Created:** 2026-05-20
**Revised:** 2026-05-20
**Depends on:** FD-036, FD-038

## Por qué el primer intento fracasó

### El problema raíz: split visual/física

`WorldRotator` es un `Spatial` que contiene el entorno visual y rota como nodo en el árbol de escena. Los objetos **dentro** de él (`canonical space`) rotan con él visualmente. Sin embargo, Godot 3 recalcula las transforms de colisión desde posiciones globales cada physics frame. Cuando `WorldRotator` rota durante un cambio de plate, cada `StaticBody` o `RigidBody` dentro de él se **teletransporta** en el espacio de física global. Esto hace que sea imposible colocar una escena con física en el espacio centrífugo: el contenido visual funciona, pero cualquier objeto dependiente de física dentro de WorldRotator se rompe en el momento en que WorldRotator rota.

El pool de colisiones (`_collision_pool`) resuelve esto para las plataformas situando los `StaticBody` **fuera** de WorldRotator y reposicionándolos cada frame para que coincidan con los transforms globales de las plates cercanas. **No existe un sistema equivalente para el contenido de escena arbitrario.**

### Consecuencia directa

No puedes autorar una escena ("sala", "puzzle", "prop interactivo") que viva permanentemente en una plate centrífuga si esa escena contiene física, porque:

1. Si la pones **dentro** de WorldRotator: la física se teletransporta al rotar.
2. Si la pones **fuera** de WorldRotator: está en espacio global con +Y fijo y no tiene la orientación correcta de la plate centrífuga.

---

## Decisión revisada

Odisea usa un modelo de gravedad híbrido en cuatro regímenes estables.

| Régimen | Runtime path | Qué se simula |
|---------|--------------|---------------|
| `STANDARD_1G` | `PlayerControllerV2` | Gravedad normal `Vector3.DOWN` |
| `SPIN_WALKABLE` | `PlayerControllerV2` + `WorldRotator` + **PlateContentStream** | Player + contenido de escena en espacio centrífugo |
| `ZERO_G` | `ControllerManager` + `ZeroGravityController` | Controlador inercial 0G separado |
| `SPIN_DYNAMIC` | `DynamicGravityProxy` (opt-in) | Pseudo-gravedad radial para props `RigidBody` seleccionados |

---

## Reglas invariantes

- No introducir `up` dinámico en `PlayerControllerV2`, `PlayerJumpV2` ni `PlayerMovementV2`.
- La ilusión de gravedad centrífuga caminable se logra **rotando el mundo visual** alrededor del jugador, no modificando la física del jugador.
- Zero-G sigue siendo un controlador separado seleccionado por `ControllerManager`.
- Coriolis y pseudo-gravedad radial son opt-in por prop/zona, no defaults globales.
- Simular sólo objetos que el jugador puede leer o usar; VFX, audio y staging para movimiento decorativo o lejano.

---

## Arquitectura revisada: PlateContentStream

### Principio

Todo el **contenido de gameplay** (props, escenas interactivas, colisiones de escena) vive en **espacio global** con orientación calculada a partir del transform global de cada plate. La `PlateContentStream` mantiene un pool de "slots" activos: para cada plate cercana, materializa su contenido en el transform global correcto, igual que el `_collision_pool` hace con los `StaticBody` de las plataformas.

```
World
├── PlayerController           ← sin cambios, UP = Vector3.UP
│   └── CameraRig
├── WorldRotator               ← solo visual: TerraceSpiral (MultiMesh), skybox, LOD lejano
│   ├── TerraceSpiral
│   └── Environment
└── PlateContentRoot           ← FUERA de WorldRotator, espacio global
    ├── SlotA  (plate 12)      ← Spatial con transform = plate_global_transform
    │   └── <sub-scene>        ← instancia de la escena de contenido de esa plate
    ├── SlotB  (plate 13)
    └── ...                    ← N slots (pool fijo, reasignados por distancia)
```

### Flujo de autorías

1. **Autoras sub-escenas en espacio local neutro**: +Y arriba, suelo en Y=0. Estándar Godot.
2. **Asocias la sub-escena a una plate** vía `PlateContentStream.assign_scene(spiral_idx, plate_idx, packed_scene)`.
3. **En runtime**, `PlateContentStream` instancia la sub-escena como hijo de un `Spatial` cuyo `global_transform` es `WorldRotator.global_transform * plate_canonical_transform`.
4. **Cuando WorldRotator rota** (player cambia de plate), `PlateContentStream` actualiza los transforms de todos los slots activos cada physics frame, igual que el pool de colisiones.
5. **Los `StaticBody` dentro de la sub-escena** son nodos hijos de un `Spatial` en espacio global — su transform se actualiza de forma estable sin teletransporte.

### Por qué esto funciona

- Los slots del `PlateContentRoot` **no son hijos de WorldRotator** — no rotan cuando WorldRotator rota.
- En lugar de eso, cada frame se recalcula `slot.global_transform = WorldRotator.global_transform * plate_canonical`.
- Esto es idéntico a lo que ya hace `_sync_pool_transforms_to_world()` para el pool de colisiones.
- Los `StaticBody` dentro de los slots se mueven suavemente (velocidad finita de rotación), no se teletransportan.

---

## Superficie de implementación

### Existente (sin cambios de contrato)

| Archivo | Rol |
|---------|-----|
| `core_v2/systems/GravityModes.gd` | Integers estables de modo para snapshots y tests |
| `core_v2/systems/GravityWorld.gd` | Resuelve modo-en-posición, zonas, basis target, selector de controlador |
| `core_v2/systems/WorldRotator.gd` | Path oficial de gravedad centrífuga caminable; sólo visual + player comfort |
| `core_v2/player/ControllerManager.gd` | Mapea `ZERO_G` → `ZeroGravityController`; resto usa controlador estándar |
| `core_v2/systems/DynamicGravityProxy.gd` | Pseudo-gravedad radial opt-in para `RigidBody` props seleccionados |

### Nuevo

| Archivo | Rol |
|---------|-----|
| `core_v2/systems/PlateContentStream.gd` | Pool de slots de contenido; mantiene sub-escenas en transforms globales correctos |
| `core_v2/components/PlateContentRoot.tscn` | Nodo raíz (fuera de WorldRotator) que contiene los slots activos |

### Contrato de PlateContentStream

```gdscript
# Asocia una escena empaquetada a una plate específica.
# La escena se instanciará cuando el jugador esté cerca de esa plate.
func assign_scene(spiral_idx: int, plate_idx: int, packed: PackedScene) -> void

# Registra el WorldRotator. Llamado automáticamente si PlateContentRoot es hijo del nivel.
func register_rotator(rotator: Spatial) -> void

# Actualiza los transforms de todos los slots activos (llamado en _physics_process).
func _sync_slot_transforms() -> void

# Devuelve el slot activo para una plate, o null si no está materializado.
func get_slot(spiral_idx: int, plate_idx: int) -> Spatial
```

---

## Regla de autorías

> **Todo contenido que tenga física (StaticBody, Area, RigidBody) DEBE vivir fuera de WorldRotator.**
> Contenido puramente visual (MeshInstance, Particles, Light) puede vivir dentro de WorldRotator.

Esto es el único cambio de disciplina respecto al primer intento. La clave es que `PlateContentStream` abstrae la complejidad de mantener los transforms correctos.

---

## Para `DynamicGravityProxy` (SPIN_DYNAMIC)

Sigue siendo válido para props `RigidBody` que deben "caer" radialmente:
- La dirección de gravedad se calcula como `(body_position - axis_origin).normalized()` (hacia afuera del eje).
- Se aplica via `add_central_force` en `_physics_process`.
- Sólo activar para objetos cuya experiencia de física sea visible al jugador.
- **No usar para objetos estáticos** (colisiones de suelo, paredes) — esos van en slots de `PlateContentStream`.

---

## Verificación

Tests existentes (sin cambios):

```bash
./runtest.sh -a ./core_v2/tests/test_gravity_modes.gd
./runtest.sh -a ./core_v2/tests/test_dynamic_gravity_proxy.gd
./runtest.sh -a ./core_v2/tests/test_world_rotator.gd
```

Tests nuevos a crear:

```bash
./runtest.sh -a ./core_v2/tests/test_plate_content_stream.gd
```

El test de `PlateContentStream` debe verificar:
1. Un slot materializado tiene `global_transform.origin` que coincide con `WorldRotator.global_transform * plate_canonical.origin` con error < 0.02.
2. Cuando WorldRotator rota 90°, el slot sigue al plate (no se queda en posición anterior).
3. Un `StaticBody` hijo del slot tiene colisión funcional (raycast desde arriba golpea el body).
4. Asignar una nueva escena a un slot la instancia correctamente como hijo del slot.
