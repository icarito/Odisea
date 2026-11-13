# Gloo endurecido como puente/escalera — verificación de colisión con el jugador

Estado: verificado (2026-11-13). No requiere cambios de producción.

## Reporte

Se reportó que el gloo endurecido «no tiene colisiones con el player», por lo que no
serviría de puente ni de escalera, atribuyéndolo a que `move_and_slide()` de un
`KinematicBody` no detecta colisión contra otro `KinematicBody` (limitación clásica de
Godot 3).

## Verificación

Con el backend actual el jugador **sí** colisiona con el gloo curado y se apoya en él.
Evidencia:

- `core_v2/tests/test_multitool_gloo.gd`:
  - `test_gloo_cured_blob_supports_player_as_bridge`: un `Pilot_v2` real (su propio
    gravity + `move_and_slide_with_snap`) cae sobre un blob curado a ras de piso y queda
    parado arriba (y≈0.49, tope del blob), no en el piso (y≈0.05).
  - `test_gloo_cured_blobs_support_player_as_ladder`: el jugador queda apoyado sobre el
    blob curado más alto de una escalera de 3 blobs (y≈1.89, tope del blob superior),
    no sobre el pedestal pelado (y≈1.45).
- Juego en vivo (peer `:4999`): disparando con `MultiToolV2.fire_gloo()`, el blob cura
  (`collision_layer = 64`, shape habilitada) y el jugador queda parado encima
  (y = 0.036 ≈ tope del blob).
- El blob curado conserva `collision_layer = 64` (capa 7, Prop) y la máscara del jugador
  (`79`, vía `PLAYER_REQUIRED_COLLISION_MASK = 1 << 6`) ya incluye esa capa.
- También se verificó con `3d/physics_engine="Bullet"` explícito: el jugador sigue
  apoyándose (Box3D y Bullet de este fork detectan KinematicBody contra KinematicBody).

## Por qué el diagnóstico previo no aplicaba

`project.godot` usaba **Bullet** hasta FD-290; desde el commit `3076d990`
(2026-09-09) usa **Box3D**. El binario stock cae a Bullet en silencio cuando no conoce
`Box3D` (`.github/README_box3d_release.md`). En el binario del fork (CI, exports,
`runtest.sh` con `platform=server`) el jugador sí colisiona con el gloo curado.

## Límites reales que sí quedan (fuera del alcance de este reporte)

1. **Anclaje dinámico**: el gloo pegado a un `RigidBody`/`KinematicBody` queda **sin**
   colisión sólida por diseño (`test_gloo_attached_to_dynamic_body_has_no_solid_collision`).
   No se puede parar sobre gloo pegado a un prop móvil.
2. **Blob en pared**: el blob sobresale ~0.43 m de la pared y el radio del jugador es
   0.5 m, así que el jugador no puede centrarse sobre él y resbala; un gloo en pared no
   sirve como escalera con el tamaño actual del blob.
