# FD-276: El Pilot se transparenta al tapar la pantalla del HoloTerminal

**Status:** In Progress
**Priority:** Medium
**Effort:** Small
**Created:** 2026-08-23
**Completed:** -

## Problem

Cuando el `Pilot_V2` (Elías) queda entre la cámara y la pantalla de un
`HoloTerminal` interactivo, su cuerpo tapa el texto del holograma y no se puede
leer. Hoy no existe ningún mecanismo que transparente al jugador frente a la
pantalla.

## Objetivo (qué se pide, sin sobre-especificar el cómo)

Cuando el cuerpo del Pilot esté tapando la pantalla de un `HoloTerminal` activo,
el Pilot debe volverse **semi-transparente** (blend suave), o en su defecto la UI
del holograma debe traslucirse de alguna manera que permita leer el texto a
través del cuerpo. El resultado visual importa más que la técnica exacta.

## Restricciones (importantes)

- **Debe ser barato.** Nada de raycasts por frame, ni queries de física, ni
  rayos contra el espacio de la escena. Usar **geometría básica barata** para
  decidir cuándo el Pilot tapa la pantalla (por ejemplo: cono/volumen cámara→pantalla
  contra el AABB o la esfera del Pilot, dot products, distancias — matemática
  pura, sin `PhysicsServer` ni `intersect_ray`).
- **El proyecto es GLES2.** El `HoloTerminal` YA es un shader con transparencia
  (`hologram`/`HoloGlass`). Por eso es probable que el efecto de transparentar al
  Pilot tenga que resolverse con **dither** (patrón de umbral + `discard` o
  `alpha_scissor`), no con alpha-blend verdadero, que en GLES2 se ordena mal con
  transparencias superpuestas. Aceptar dither como solución si blend no se ve bien.
- **Godot 3.x / GDScript 1.x**: `yield`, nunca `await`. Sin `@onready`.
- No romper el determinismo de replay: el efecto es **visual puro** y no debe
  escribir estado que viaje en snapshots (`get_snapshot()`/`restore_snapshot()`).

## Punto de partida (referencias, no solución cerrada)

- `core_v2/actors/Pilot_v2.tscn` — modelo del jugador (`Pilot.glb`, importado).
  Revisar qué `MeshInstance`/`Skeleton` componen el cuerpo y qué material(es)
  habría que volver transparente.
- `core_v2/things/HoloTerminalV2.gd` — la pantalla vive en el subnodo de
  `ViewportTexture` (buscar el mesh de la pantalla, típicamente `ScreenMesh` o
  similar); el terminal tiene estado activo/focus (`set_active()`, `_is_focused`).
- `core_v2/autoloads/PropDitherManager.gd` + `shaders/prop_dither_occlusion.gdshader` —
  patrón ya probado de "cono cámara→jugador" que alimenta uniforms por frame
  (`player_pos`/`camera_pos`/`is_active`/`hole_radius`) y descarta fragmentos con
  `discard` (Bayer/IGN). Es el modelo a imitar, pero con el punto de interés
  puesto en la **pantalla del holograma**, no en el jugador.
- `core_v2/components/PlayerXRayOverlay.gd` + `core_v2/visual/player_xray.shader` —
  existe un "ghost pass" de jugador (depth_test_disable, unshaded, rim naranja
  pulsante). **Hoy NO está instanciado en ninguna escena** (código muerto). Sirve
  como referencia de cómo aplicar un material de "ver a través", pero su look
  (naranja pulsante) NO es el pedido: se busca transparencia neutra que conserve
  el color/iluminación del cuerpo.

## Dirección sugerida (Jules elige la implementación final)

1. Detectar, de forma barata, cuándo el cuerpo del Pilot está entre la cámara y la
   pantalla del `HoloTerminal` activo (volumen cónico o test de planos contra el
   AABB/esfera del Pilot; sin raycasts de física).
2. Aplicar transparencia **suave y proporcional** a cuánto tapa la pantalla (fade,
   no parpadeo on/off).
3. Si alpha-blend no se ve bien en GLES2 por la transparencia del holograma,
   resolver con **dither** (umbral + `discard`/`alpha_scissor`), reutilizando el
   estilo de `prop_dither_occlusion.gdshader`.
4. Aplicar solo cuando el terminal está activo/interactuando, para no transparentar
   al Pilot frente a pantallas apagadas.

## Archivos probables

- `core_v2/actors/Pilot_v2.tscn` (material del cuerpo a transparentar)
- `core_v2/things/HoloTerminalV2.gd` (detección del bloqueo de pantalla)
- shader nuevo o reutilizado bajo `shaders/` o `core_v2/visual/`
- posiblemente un helper nuevo (componente/autoload) para el test de geometría barata

## Reglas

- Godot 3.x / GLES2. Sin `await`, sin `@onready`.
- Barato: matemática/geometría pura, sin raycasts de física ni `intersect_ray`.
- No tocar el determinismo de replay (el efecto es solo visual).
- No romper el `PropDitherManager` existente ni la oclusión de props.

## Verificación

1. Con un `HoloTerminal` activo, acercar al Pilot entre la cámara y la pantalla:
   el cuerpo se transparenta lo suficiente para leer el texto.
2. Al apartarse, el Pilot recupera su opacidad normal sin parpadeo brusco.
3. Frente a pantallas apagadas, el Pilot NO se transparenta.
4. `./runtest.sh -a ./core_v2/tests/` no rompe las pruebas existentes.

Cuando termines, publicá el PR contra `main` con el spec y el diff. **No mergear sin OK explícito.**
