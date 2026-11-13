# FD-233 — ZeroGravityController: capa de inercia newtoniana

## Problema

El ZeroGravityController actual usa `KinematicBody` con `linear_interpolate` para acercar la velocidad al target. Esto produce un dampening artificial: la aceleración es exponencial y al soltar el input la velocidad muere rápido por el `idle_damping` multiplicativo.

En zero-G real, el jugador debería sentir **inercia**: acelerar toma tiempo (como empujar una masa), y al soltar el input la velocidad residual persiste (flotar en el espacio). La fricción debería ser mínima o configurable.

## Solución

Añadir una **capa de inercia newtoniana** inspirada en el alma RigidBody del `PushableBoxV2`, pero sin cambiar el `KinematicBody` del player:

1. El input del jugador genera una **fuerza** (no velocidad directa)
2. La fuerza se convierte en aceleración: `acceleration = force / mass`
3. La velocidad resultante es: `velocity += acceleration * dt`
4. Un `inertia_factor` (0.0–1.0) mezcla el comportamiento actual con el nuevo

### Fórmula

```
// Comportamiento actual (cinemático)
target_v = move_dir * max_speed * sprint_mult
kinematic_v = lerp(current_v, target_v, accel * dt)

// Comportamiento inercial (newtoniano)
force = move_dir * max_speed * sprint_mult * thrust_force
inertia_accel = force / mass
inertia_v = current_v + inertia_accel * dt
inertia_v *= space_damping  // fricción espacial mínima (0.995–1.0)

// Mezcla final
velocity = lerp(kinematic_v, inertia_v, inertia_factor)
```

### Parámetros nuevos (en ZeroGravitySettings)

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `inertia_factor` | `0.3` | 0.0 = cinemático puro, 1.0 = inercia pura |
| `thrust_force` | `40.0` | Fuerza de empuje del input (N) |
| `mass` | `80.0` | Masa del jugador en zero-G (kg) |
| `space_damping` | `0.998` | Fricción espacial por frame (0.995–1.0, multiplicativo) |
| `max_inertia_speed` | `12.0` | Cap absoluto de velocidad inercial (m/s) |

### Determinismo (snapshots)

La capa de inercia usa solo variables determinísticas:
- `velocity` (ya está en snapshot del KinematicBody)
- No depende de `move_and_slide` ni colisiones para el cálculo de inercia
- El `space_damping` es multiplicativo puro, frame-rate independiente con `pow(damping, dt * 60.0)`

El snapshot del ZeroGravityController ya se guarda vía `get_snapshot()` / `restore_snapshot()` en el SessionManager. Solo hay que asegurar que `velocity` esté incluido.

### Idle damping vs space damping

- **Comportamiento actual**: `idle_damping` multiplica la velocidad por ~0.95 cada frame cuando no hay input → se frena rápido
- **Comportamiento inercial**: `space_damping` es mucho más suave (~0.998) → el jugador flota
- Cuando `inertia_factor > 0`, el idle damping del modo cinemático no se aplica (porque la inercia ya tiene su propio damping espacial)

## Scope

- Modificar `core_v2/player/ZeroGravityController.gd`: añadir cálculo de inercia newtoniana y mezcla con `inertia_factor`
- Modificar `core_v2/player/ZeroGravitySettings.gd`: añadir nuevos exports
- Asegurar snapshots incluyen la velocidad inercial
- No modificar el PlayerController base ni otros controladores
- No cambiar el KinematicBody a RigidBody (el player sigue siendo KinematicBody)

## Verificación

- Con `inertia_factor = 0.0`: comportamiento idéntico al actual (regresión)
- Con `inertia_factor = 1.0`: el jugador acelera progresivamente, flota al soltar input, rebota elásticamente contra paredes (vía `move_and_slide`)
- Con `inertia_factor = 0.5`: mezcla suave entre ambos
- Replay determinístico: misma secuencia de input produce misma trayectoria

## Out of scope

- No modificar el sistema de colisiones
- No añadir rotación inercial (solo traslación)
- No afectar gravedad normal (solo zero-G)
- No modificar el PushableBoxV2

## Archivos afectados

- `core_v2/player/ZeroGravityController.gd`
- `core_v2/player/ZeroGravitySettings.gd`
