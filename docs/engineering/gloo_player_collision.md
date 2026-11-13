# Gloo endurecido como puente/escalera

## Reporte

El gloo endurecido servía de puente a ras de piso pero **no de escalera en pared**: el
jugador resbalaba del blob anclado a una superficie vertical.

## Causa

En el backend Box3D (y con Bullet explícito) el jugador **sí** colisiona con el gloo
curado (`collision_layer = 64` ⊂ máscara del jugador `79`); la limitación clásica de
Godot 3 «`move_and_slide` no detecta contra otro `KinematicBody`» **no aplica** aquí.
El problema era geométrico: la esfera curada sobresale ~0.43 m de la pared y el radio del
jugador es 0.5 m, así que el jugador no puede centrarse sobre ella y el contacto queda
demasiado inclinado (> `floor_max_angle` de 45° en cuanto se aleja del borde) → resbala.

## Fix

`MultiToolGlooProjectile` agrega un **segundo `CollisionShape`** (`SolidLedgeShape`, una
`BoxShape` plana) al mismo cuerpo del blob:

- Se habilita sólo cuando el blob queda sólido (`_set_solid_collision(true, ...)`).
- Es una superficie **horizontal pisable** con el tope a la altura del tope del blob,
  centrada en el blob para anclajes horizontales (piso/techo) y extendida
  `solid_ledge_reach` (0.5 m) hacia afuera de la superficie para anclajes verticales
  (pared), usando la normal de anclaje (`_stick_normal`).
- Vive en el **mismo cuerpo** que la esfera, así que no agrega un objetivo de raycast
  nuevo ni colisionadores extra: el determinismo del gloo en vuelo no cambia.

No se tocó `PlayerControllerV2.gd` ni la máscara del jugador. La escena
`MultiToolGloo.tscn` no cambia: la repisa se crea en código (`_ready`) para no alterar el
tipo de nodo del proyectil (que debe seguir siendo `KinematicBody` para volar con
`move_and_collide`).

## Verificación

- `test_gloo_cured_blob_supports_player_as_bridge`: puente a ras de piso (y≈0.49).
- `test_gloo_cured_blobs_support_player_as_ladder`: escalera de 3 blobs en altura
  (y≈1.89).
- `test_gloo_cured_wall_blob_supports_player_as_step`: blob en pared, el jugador se para
  sobre la repisa (y>2.1) aunque se acerque lejos del borde (antes resbalaba con
  spawn_x≥0.7).
- `test_gloo_cured_wall_blobs_support_player_as_ladder`: escalera de 3 blobs en pared, el
  jugador queda apoyado en el blob más alto (y≈2.76).
- `test_determinism_v2` verde.

## Límites (documentados)

1. **Anclaje dinámico**: el gloo pegado a un `RigidBody`/`KinematicBody` queda sin
   colisión sólida por diseño (`test_gloo_attached_to_dynamic_body_has_no_solid_collision`).
2. **Separación vertical**: el jugador mide 2 m, así que un blob directamente encima de
   otro a menos de ~2.4 m actúa de techo. Una escalera de pared usable necesita esa
   separación entre blobs (o acercarse por el borde externo de la repisa).
