# FD-246: Duct Maze Zero-G Collision Hardening

**Status:** spec  
**Author:** Odiseo  
**Date:** 2026-07-01  
**Branch:** `feature/FD-246-duct-collision-fix`  
**Target:** Godot 3.x, GDScript 1.x

---

## Overview

Refuerza la colisión de los ductos del `DuctMazeStreamer` para eliminar el clipping del player en zero-G, donde atraviesa las paredes de los ductos "hasta la mitad del cuerpo".

## Root Cause Analysis

Todas las tiles del duct maze YA generan colisión. El problema es **tunneling cinemático** en zero-G:

| Factor | Valor | Impacto |
|--------|-------|---------|
| Espesor de pared | `DUCT_WALL_DEPTH = 0.6m` | Un frame a 16 m/s con 30fps = 0.53m de desplazamiento, casi todo el espesor |
| Cara interna del collider | `radius - 0.05m` (2.65m) | La pared visual interna está a 2.7m — el collider está 5cm DENTRO de la visual |
| Radio de cápsula del player | 0.5m | El centro del player se detiene a 2.15m del eje, cuerpo a 2.65m |
| Tipo de collider en junctions/capsules | `create_trimesh_shape()` (ConcavePolygonShape) | Trimesh es más propenso a tunneling que primitivas convexas |

**Conclusión:** 0.6m de espesor es insuficiente para velocidades zero-G (8-16 m/s). Los boxes planos del anillo de 8 caras dejan crestas donde el player puede "resbalar" hacia dentro. Las junctions usan trimesh que Godot Physics maneja peor.

## Scope

### In Scope
1. Aumentar `DUCT_WALL_DEPTH` de 0.6m → 1.2m
2. Mover cara interna del collider de `radius - 0.05` → `radius + 0.05` (ligeramente fuera de la pared visual)
3. Reemplazar `create_trimesh_shape()` en junctions/capsules por box-ring equivalente (`_add_facet_ring`)
4. Aumentar `DUCT_COLLISION_FACETS` de 8 → 12 para mejor aproximación del cilindro

### Out of Scope
- Continuous Collision Detection (CCD) en Godot 3 (no soportado nativamente)
- Cambios en el player controller
- Modificaciones al sistema de streaming

## Files

### Modify
| File | Change |
|------|--------|
| `core_v2/systems/DuctMazeStreamer.gd` | Cambiar constantes + reemplazar trimesh en junctions/capsules |

## Detailed Spec

### 1. Constantes

```gdscript
# Before:
const DUCT_COLLISION_FACETS := 8
const DUCT_WALL_DEPTH := 0.6

# After:
const DUCT_COLLISION_FACETS := 12
const DUCT_WALL_DEPTH := 1.2
```

### 2. Offset de cara interna

En `_add_facet_ring`, cambiar el cálculo de `centre`:

```gdscript
# Before (línea ~649):
var centre := outward * (radius - 0.05 + wall * 0.5)

# After:
var centre := outward * (radius + 0.05 + wall * 0.5)
```

Esto mueve la cara interna del collider 5cm FUERA de la pared visual, eliminando la brecha de 5cm que existía. Con `DUCT_WALL_DEPTH = 1.2`, el collider cubre desde `radius + 0.05` hasta `radius + 1.25`, asegurando que el player no pueda penetrar la pared visual incluso con el radio de cápsula de 0.5m.

### 3. Junctions — reemplazar trimesh por box-ring

En `make_junction`, eliminar el bloque que usa `create_trimesh_shape()`:

```gdscript
# REMOVE:
var hub_col = CollisionShape.new()
hub_col.shape = hub.mesh.create_trimesh_shape()
```

Reemplazar con un box-ring esférico que envuelva el hub. Como las junctions son hubs esféricos de radio `hub_radius = duct_radius * 1.6 ≈ 4.32m`, usar `_add_facet_ring` no es adecuado (es para cilindros). En su lugar, construir `N` anillos de cajas a diferentes latitudes (como los paralelos de un globo), o usar un enfoque más simple: un `CollisionShape` con `SphereShape` sólido que ocupe todo el hub. Como el hub ya tiene bocas perforadas visualmente, si el collider es una esfera sólida, bloqueará las bocas. Pero en zero-G dentro del duct maze, el player NUNCA necesita cruzar las bocas de los hubs por dentro — los hubs son puntos de cruce, el player pasa a través de ellos por las bocas abiertas.

**Decisión de diseño:** Usar un `SphereShape` sólido para el hub con radio `hub_radius + wall*0.5`. Esto es seguro porque:
- Las bocas del hub se conectan a brazos que ya tienen su propia colisión
- El player en zero-G viaja POR DENTRO de los ductos y cruza los hubs por las bocas
- La esfera sólida evita que el player "caiga" dentro del hub desde fuera

**Alternativa más precisa pero más compleja:** Construir una "jaula" de boxes alrededor del hub, similar al approach de `_add_facet_ring` pero en 3D (anillos a múltiples latitudes). Esto mantiene las bocas abiertas.

**Recomendación para Jules:** Implementar la alternativa de jaula 3D (anillos a 3 latitudes: ecuador, +45°, -45°). Cada anillo usa `_add_facet_ring` con el radio efectivo a esa latitud (`hub_radius * cos(lat)`). Esto da cobertura completa sin tapar las bocas.

Pseudocódigo para `make_junction` hub collision:
```gdscript
# Reemplazar el bloque hub_body existente por:
var hub_body = StaticBody.new()
hub_body.name = "HubCollision"
hub_body.collision_layer = DUCT_LAYER
hub_body.collision_mask = 255

var ring_angles = [0.0, PI/4, -PI/4]  # ecuador, +45°, -45°
for lat in ring_angles:
    var ring_radius = hub_radius * cos(lat)
    var ring_y = hub_radius * sin(lat)
    var xform = Transform(Basis(), Vector3(0, ring_y, 0))
    # Usar half_len suficiente para cubrir el gap entre anillos
    var vertical_spacing = hub_radius * 0.8  # generoso para que se solapen
    _add_facet_ring_lat(hub_body, ring_radius, vertical_spacing, xform)

root.add_child(hub_body)
```

### 4. Capsules — reemplazar trimesh por esfera sólida

En `make_capsule`, mismo approach que junctions. El `CapsuleShellCollision` actual usa `create_trimesh_shape()`. Reemplazar por una jaula 3D o, más simple, una `SphereShape` sólida (la cápsula es un cuarto cerrado, el player solo entra/sale por las bocas que ya tienen brazos con colisión).

Usar `SphereShape` sólido con radio `hub_radius + wall*0.5`:

```gdscript
# REMOVE el trimesh:
# hub_col.shape = hub.mesh.create_trimesh_shape()

# REPLACE con:
var hub_col = CollisionShape.new()
var sphere = SphereShape.new()
sphere.radius = hub_radius + DUCT_WALL_DEPTH * 0.5
hub_col.shape = sphere
```

## Acceptance Criteria

1. Player en zero-G no atraviesa las paredes de ductos rectos (DuctRadial)
2. Player en zero-G no atraviesa las paredes de ductos curvos (DuctArc)
3. Player no se "traga" dentro de junctions (C, T, X)
4. Player no atraviesa las paredes de capsule rooms
5. El paso por bocas de hub sigue siendo posible (no bloqueado por collider nuevo)
6. No hay gaps en costuras entre tiles adyacentes
7. Sin regresión de rendimiento: el número total de collision shapes no aumenta más de 2x

## Dependencies

- Ninguna. Solo modifica `DuctMazeStreamer.gd`.

## Risks

- **Bocas bloqueadas**: si la jaula 3D en junctions es demasiado densa, podría bloquear las bocas. Mitigación: usar solo 3 anillos (ecuador, ±45°), no una esfera completa.
- **Rendimiento**: 12 facets × 3 anillos × N junctions = más collision shapes. Mitigación: el número es bajo (decenas, no cientos).
- **Ajuste visual**: la cara interna ahora está 5cm fuera de la visual. En la práctica es imperceptible (5cm en un ducto de 2.7m de radio).
