# FD-261: Dome_Intro — bake de red de tuberías y letreros

**Status:** Implemented
**Priority:** P2
**Effort:** Small
**Created:** 2026-08-17

## Problem

El trabajo reciente de tuberías/válvulas (FD-044, FD-255/256) y de señalización
(FD-260) agregó, en `Dome_Intro.tscn`, 14 instancias de tubería
(`PipeSection`/`PipeTee`, cada una con su propio `MeshInstance` +
`StaticBody`/`CollisionShape`) y 12 `SignagePanel` (cada uno con su propio
`Viewport` en vivo renderizando texto a una textura única). Eso midió una
regresión de rendimiento en el port de Android: son ~14 draw calls y ~14
objetos de colisión de tuberías sin batching posible, más 12 draw calls de
letreros con textura única cada uno (sin batching) y 12 `Viewport` en VRAM.

## Solution

Extiende el patrón de FD-250 (fuente editable → bake determinista → producto
runtime), ya usado para andamios (`tools/bake_scaffold_walkways.gd`) y
criopods, a estos dos sistemas.

**Red de tuberías** (`tools/bake_pipe_network.gd`): cada uno de los tres
grupos `Pipes` (`CryoLoopWest`, `CryoLoopEast`, `TowerCoolantRiser`) se funde
en un `MeshInstance` combinado + un `StaticBody` (reusando los
`CollisionShape` originales, mismo criterio que el bake de andamios: no
trimeshear la malla visual). Las cinco válvulas `CoolantValve` (interactivas)
y los cinco `TowerCoolantRings` (CSG, costo menor) quedan fuera del bake.
`PipeCoolantRun.gd` no cambió: ya recorre `get_children()` buscando
`MeshInstance` y pisa `surface 0`; después del bake hay un solo hijo en vez de
varios.

**Letreros** (`tools/bake_signage_panels.gd`): los 16 `SignagePanel` estáticos
(12 de `EnvironmentalSignage` + los 4 `ExitNorth/South/East/West`, movidos a
la fuente porque vivían sueltos dentro de la subescena de cada airlock en vez
de junto a los demás) se funden en un `MeshInstance` doble-cara + un
`StaticBody`. Cada texto se renderiza una vez en su `Viewport` de origen
(mismo timing que usa el panel en runtime), se captura a un atlas 4×4
compartido (`DomeIntro_SignageAtlas.tres`), y la geometría se reconstruye a
partir del propio `QuadMesh` de cada panel (remapeando su UV al atlas, sin
tocar posiciones/normales) más una cara trasera horneada directamente en la
geometría (mismo mapeo V que el frente, sólo U espejado — ver el fix de
V-flip más abajo) — reemplaza el flip por shader de `HoloGlass` en runtime
por geometría doble simple con un único `SpatialMaterial` sin sombreado,
**opaco** (ver más abajo por qué). Los textos largos usan `\n` explícito en
vez de `" // "` para aprovechar mejor el letrero (auto-fit de fuente, sin
`font_size` fijo). Los dos `LoopLabel` de las corridas de coolant quedan
fuera de este bake (no investigados; candidato para una pasada futura si el
perfil todavía lo pide).

## Files Created/Modified

- `core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn` (new, fuente)
- `core_v2/levels/interiors/DomeIntro_SignageSource.tscn` (new, fuente)
- `tools/bake_pipe_network.gd` (new)
- `tools/bake_signage_panels.gd` (new)
- `tools/verify_pipe_network_bake.gd` (new)
- `tools/verify_signage_bake.gd` (new)
- `core_v2/levels/interiors/Dome_Intro.tscn` (modify — productos horneados,
  además de quitar `CyanOmniLight`, ver abajo)
- `core_v2/props/doors/AirlockChamber.tscn` (modify — fix no relacionado, ver
  abajo)
- `core_v2/autoloads/PropDitherManager.gd` (modify — variante unshaded, ver
  abajo)
- `shaders/prop_dither_occlusion_unshaded.gdshader` (new)
- `core_v2/things/HoloTerminalV2.gd`, `core_v2/things/CoolantSystemStatusUI.gd`
  (modify — throttle de Viewport para dashboards estáticos, ver abajo)
- `core_v2/ui/MobileUI.tscn`, `core_v2/ui/TouchActionButton.gd` (modify — fuera
  de alcance de este FD, ver Out of Scope)

## Iteración: dos bugs reales del bake de letreros, y sus causas de fondo

El primer intento de bake usó un material **transparente** (para replicar el
doble-cara del `HoloGlass` original). Eso rompió el orden de dibujo contra
otros objetos transparentes de la escena (el holoterminal colgante): Godot
ordena objetos transparentes por distancia usando el AABB del `MeshInstance`
completo, y el combinado de los 12 paneles abarca el domo entero
(32×23×32 m) — un único punto de "distancia" no puede representar 12
posiciones reales, así que el mesh entero se ordenaba mal contra un objeto
transparente cercano a un panel puntual. Fix: el contenido real de estos 12
paneles siempre fue opaco (`panel_alpha=1.0`, `hologram_mode=false` en los
doce), así que no hacía falta transparencia — pasar a `flags_transparent =
false` usa el z-buffer normal, que no depende del orden de dibujo.

Eso destapó un segundo bug: **opaco** hace al material elegible para
`PropDitherManager` (que envuelve props en `collision_layer` 64 con un
shader de oclusión cono cámara-jugador). Los paneles originales usaban un
`ShaderMaterial` (`HoloGlass`), que ese scanner nunca toca — el bake, al usar
`SpatialMaterial`, quedó expuesto por primera vez. El shader de oclusión
existente (`prop_dither_occlusion.gdshader`) es `spatial` sin `unshaded` en
`render_mode` (correcto para props con PBR real), así que un material
pensado para verse siempre a full brillo se veía apagado/oscuro bajo la
iluminación tenue de Dome_Intro una vez envuelto. La oclusión en sí es
importante (no se saca al panel del sistema); el fix es una tercera variante
de shader, `prop_dither_occlusion_unshaded.gdshader` — mismo descarte cónico,
pero sin pase de luz — seleccionada en
`PropDitherManager._convert_spatial_to_dither` cuando
`source.flags_unshaded` es true.

## Bugs relacionados corregidos en la misma pasada

**Frost del airlock más cercano.** `AirlockPool.gd` monta un único
`AirlockChamber` compartido sobre el shell más cercano al jugador, ocultando
las mallas `ice_freezable` de ese shell. El `AirlockChamber` nunca tuvo el
grupo `ice_freezable`, así que `IceObjectFreezer` nunca envolvía sus
materiales: el airlock más cercano perdía la escarcha mientras los otros tres
(shells sin montar) la conservaban. Fix de una línea:
`AirlockChamber.tscn` ahora lleva `groups=["ice_freezable"]` en su raíz — no
hace falta tocar `AirlockPool.gd` porque la instancia compartida se crea una
sola vez y ya existe en el árbol antes del primer scan de `IceObjectFreezer`.

**Luz realtime sin presupuestar.** `CyanOmniLight` (`light_bake_mode =
DISABLED`, realtime completo) se agregó en el mismo commit que las tuberías
de coolant (`4d30e10c`), colgado de `SuspendedCryoDiagnostics/Carriage` — la
misma pantalla colgante señalada como sospechosa de lentitud. Nunca la toca
ningún script (puramente decorativa) y quedaba fuera del presupuesto de
iluminación dinámica que documenta FD-250. Se eliminó.

**Viewport del holoterminal colgante redibujando cada frame sin necesidad.**
`HoloTerminalV2._update_visuals()` ya throttlea el `Viewport` por distancia/
foco (`UPDATE_WHEN_VISIBLE` si el jugador está cerca, `UPDATE_ALWAYS` si está
en foco), pero para el panel `HangingDisplay` eso sigue siendo un redibujado
completo cada frame mientras el jugador esté cerca — y su contenido
(`CoolantSystemStatusUI`) sólo cambia cuando una válvula cambia de estado,
evento poco frecuente. Se agregó `static_content` (export bool, default
false — no toca ningún otro terminal): en reposo el viewport quesa en
`UPDATE_DISABLED` y sólo pulsa `UPDATE_ONCE` en el primer frame visible o
cuando algo llama a `request_redraw()`; `CoolantSystemStatusUI` lo llama tras
actualizar una fila. Como `InteractableBaseV2` apaga `_physics_process` en
reposo (FD-224), hizo falta overridear `_wants_continuous_step()` para que el
pedido de redibujado realmente llegue a correr, y `request_redraw()` llama
`set_physics_process(true)` para sacarlo de reposo de inmediato.
`HangingDisplay` en `Dome_Intro.tscn` es la única instancia con
`static_content = true`.

## Verification

1. `tools/verify_pipe_network_bake.gd` — triángulos y `CollisionShape` por
   grupo, fuente vs. producto.
2. `tools/verify_signage_bake.gd` — triángulos (front + back espejado por
   panel doble-cara) y `CollisionShape`, fuente vs. producto.
3. `./runtest.sh -a ./core_v2/tests/` — 103 tests, incluye los de airlock
   (`test_dome_crio_airlock_*`) — todos pasan, repetido después de cada ronda
   de fixes.
4. `python3 scripts/check_tracked_imports.py` y
   `python3 scripts/check_critical_import_artifacts.py` — OK.
5. Inspección visual: `DomeIntro_SignageAtlas_preview.png` (atlas legible),
   render headless front/back de paneles horneados con distintas rotaciones
   (texto derecho, sin espejar, sin invertir), y verificación scriptada de
   `PropDitherManager._can_apply_occlusion_dither` /
   `_convert_spatial_to_dither` contra el material horneado real.
6. Validación on-device Android (`make android-install` + bridge ANNA V2):
   confirmado en el dispositivo real (Redmi Note 9 Pro, GLES2/ETC1) — flujo de
   coolant visible, frost del airlock más cercano confirmado
   mecánicamente (`is_in_group("ice_freezable")` + `next_pass` en el material
   del chamber montado), letreros legibles. La comparación de draw calls
   antes/después no se hizo 1:1 en el mismo dispositivo/vista (sólo se probó
   el estado "después"); la reducción real está confirmada por el propio bake
   (29→4 draw calls entre tuberías y letreros) más el descarte de la luz
   realtime extra.

## Out of Scope

- `TowerCoolantRings` (5 `CSGTorus`) y los 6 `SignagePanel` fuera de
  `EnvironmentalSignage` (4 salidas de airlock + 2 `LoopLabel`) — costo menor,
  no incluidos en esta pasada.
- Cambios al shader `HoloScreen`/`HoloGlass` en sí (más allá del throttle de
  `render_target_update_mode` para `static_content`).
- Ajustes de UI móvil (posición cruz de botones, foco/hover atascado por
  emulación de mouse táctil, fuente/contraste, rango del joystick) — se
  hicieron en la misma sesión pero son un tema aparte, no forman parte de este
  FD.
