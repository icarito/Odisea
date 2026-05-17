# FD-037: Infinite Scaffold Field

**Status:** Design
**Priority:** Medium
**Effort:** Large
**Created:** 2026-05-17
**Completed:** -

## Problem

Las terrazas rotatorias necesitan un fondo estructural creible entre el shaft principal y el casco exterior de la nave. Modelar ese volumen a mano como miles de tuberias, cruces y soportes no escala: aumenta costo de authoring, costo de carga, draw calls y riesgo de que el jugador vea huecos cuando el nivel rota o se streamea.

El objetivo no es generar terreno tipo heightmap, sino un **campo procedural de andamiaje industrial**: tuberias, travesanos, abrazaderas, intersecciones y placas tecnicas que parezcan continuar indefinidamente alrededor del jugador, con detalle real solo cerca de camara.

Restricciones criticas:

- Debe ocupar el espacio entre el shaft de terrazas rotatorias y el casco exterior de la nave.
- Debe ser eficiente en GLES2 / Godot 3.6.
- Debe trabajar en coordenadas globales canonicas, no depender del origen local de un chunk visible.
- Debe ser compatible con el `WorldRotator` de FD-036: si el mundo rota para mantener al jugador en gravedad estandar, el andamiaje debe rotar junto al entorno sin popping.
- Debe permitir marcar areas donde el andamiaje no aparece. La API preferida son **areas de exclusion**, no areas de inclusion.
- Debe respetar el sistema de coordenadas del proyecto: `+Z` es back/camera direction y `-Z` es forward.

## Solution

Crear un generador visual llamado `InfiniteScaffoldField` que construye una grilla procedural alrededor de la posicion canonica del jugador. La grilla usa celdas espaciales deterministicas de 5m, con intersecciones principales aproximadamente cada 5m y variaciones seeded por coordenada de celda.

La implementacion debe separar tres conceptos:

1. **Dominio canonico**: volumen matematico del campo, expresado en coordenadas globales de nave.
2. **Exclusiones**: volumenes authorables que restan espacio al dominio canonico.
3. **Representacion visual**: chunks cercanos con meshes simples o `MultiMesh`, LOD medio con impostores, LOD lejano con shader/parallax.

### WorldRotator Contract

El nodo visual debe vivir bajo el arbol rotado por `WorldRotator` para que su orientacion sea coherente con terrazas, casco y ambiente. Sin embargo, sus decisiones de streaming se calculan en una coordenada canonica estable:

```
World
+-- PlayerController
+-- WorldRotator
|   +-- TerraceContainer
|   +-- HullShell
|   +-- InfiniteScaffoldField
+-- GravityZoneVolumes
```

`InfiniteScaffoldField` recibe o encuentra:

- `player_path`: jugador/camara usado como centro de interes.
- `world_rotator_path`: nodo que convierte entre mundo fisico actual y espacio canonico de nave.
- `shaft_radius`: radio interno reservado para el shaft de terrazas.
- `hull_radius`: radio externo aproximado del casco.
- `field_height_min` / `field_height_max`: limites axiales o verticales del volumen jugable.

Para evitar popping durante rotaciones, el generador calcula `canonical_player_pos` usando la inversa del transform del `WorldRotator` cuando aplique. El set de celdas activas depende de esa posicion canonica, no del `global_transform.origin` post-rotacion.

### Scaffold Domain

El dominio base es un volumen anular/cilindrico:

- Interior excluido: `r < shaft_radius + shaft_clearance`
- Exterior excluido: `r > hull_radius - hull_clearance`
- Altura excluida: fuera de `[field_height_min, field_height_max]`

Donde `r` se calcula en el plano radial de la nave segun el frame canonico del nivel. La implementacion inicial puede usar cilindro alrededor de `Vector3.UP`; si FD-036 define un eje distinto para TerraceSpiral, el campo debe tomar ese eje desde `GravityWorld` o una propiedad exportada.

### Exclusion Areas

La authoring API principal es `ScaffoldExclusionArea`:

- `shape`: box, sphere, cylinder o custom convex aproximado.
- `priority`: para resolver overlaps si luego hay inclusiones puntuales.
- `soft_margin`: distancia de fade visual antes de cortar andamiaje.
- `affects_lod`: permite excluir solo detalle cercano o todo el campo.
- `debug_draw`: muestra bounds en editor/test.

Ejemplos de uso:

- Cortar el volumen ocupado por una terraza.
- Abrir tuneles, puertas, shafts secundarios o zonas narrativas.
- Evitar que tuberias crucen areas de gameplay, plataformas moviles o cinematicas.
- Reservar espacio para props grandes o set pieces.

La primera version no necesita areas de inclusion. El campo existe por defecto dentro del dominio anular y las exclusiones lo recortan.

### Cell Grid

El grid canonico usa:

- `cell_size`: 5.0m por defecto.
- `detail_radius`: 18m a 25m alrededor de la camara.
- `mid_radius`: 50m a 80m.
- `far_radius`: 120m o mas, visualizado solo como capas baratas.

Cada celda genera un patron deterministico:

- Interseccion principal en el centro o en bordes compartidos.
- 2-4 tuberias en ejes canonicos, con variacion de grosor.
- Algunos soportes diagonales de baja frecuencia.
- Placas, brackets y luces pequenas solo en LOD cercano.
- Variacion seeded por `hash(cell_coord, scaffold_seed)` para que el campo no cambie al recargar.

Las celdas deben ser independientes. No debe haber estado global aleatorio que haga imposible reproducir el mismo resultado por coordenada.

### LOD Strategy

LOD cercano:

- `MultiMeshInstance` por tipo de pieza: tuberia recta, codo, union, clamp, placa.
- Meshes low-poly compartidos, materiales compartidos.
- Sin colision por defecto. Si se necesita gameplay, se authora colision puntual separada.
- Actualizacion amortizada: reciclar celdas en un presupuesto de N celdas por frame.

LOD medio:

- Tuberias simplificadas: menos piezas, sin clamps, sin detalles pequenos.
- Segmentos largos por celda o por corrida.
- Material sin luces dinamicas costosas.

LOD lejano:

- Planos/curtains o bandas cilindricas con shader de grid industrial.
- Parallax o faux-depth para sugerir capas de tuberias.
- Puede usar textura procedural/baked de andamiaje con scrolling minimo o ruido estatico.
- Nunca debe crear miles de instancias lejanas.

El generador debe exponer switches para bajar calidad:

- `enable_far_parallax`
- `enable_mid_lod`
- `max_near_cells`
- `max_multimesh_instances`
- `update_budget_per_frame`

### Visual Direction

El andamiaje debe leerse como infraestructura de nave, no como cueva natural:

- Tuberias con intersecciones cada ~5m.
- Secciones rectas, abrazaderas, codos y soportes diagonales.
- Materiales oscuros/metalicos con marcas tecnicas de bajo contraste.
- Luces de mantenimiento frias o de advertencia muy contenidas.
- Silueta densa en periferia, pero huecos claros cerca de rutas de gameplay.

El campo debe poder tener zonas tematicas por seed o perfil:

- `industrial_default`
- `cryogenic_service`
- `reactor_warning`
- `habitat_maintenance`

La variacion visual debe salir de perfiles de datos, no de hardcode disperso.

### Runtime Ownership

Nuevo codigo en `core_v2`, siguiendo la norma del proyecto.

Propuesta de nodos:

```
InfiniteScaffoldField (Spatial)
+-- NearScaffoldMultiMeshes
+-- MidScaffoldMultiMeshes
+-- FarScaffoldParallaxShell
+-- DebugOverlay
```

El sistema debe evitar `_process()` para decisiones deterministas de simulacion. Como el campo es visual, puede actualizarse en `_process()` si no afecta gameplay, pero cualquier test reproducible debe poder forzar `rebuild_around(canonical_pos)` manualmente.

## Considered Options

- **Option A: Authoring manual de chunks de andamiaje**: Control visual maximo, pero alto costo de memoria, carga y mantenimiento.
- **Option B: Generador mesh completo por chunk cercano**: Flexible, pero puede causar stalls si se reconstruyen `ArrayMesh` grandes durante runtime.
- **Option C: MultiMesh cercano + impostores/parallax lejano + exclusiones authorables**: Mejor balance para Godot 3.6/GLES2. Mantiene bajo el numero de draw calls, permite streaming por celda y conserva authoring simple.
- **Selected**: Option C.

## Files to Create

- `core_v2/systems/scaffold/InfiniteScaffoldField.gd`
- `core_v2/systems/scaffold/ScaffoldCell.gd`
- `core_v2/systems/scaffold/ScaffoldProfile.gd`
- `core_v2/systems/scaffold/ScaffoldExclusionArea.gd`
- `core_v2/systems/scaffold/ScaffoldExclusionArea.tscn`
- `core_v2/systems/scaffold/InfiniteScaffoldField.tscn`
- `core_v2/systems/scaffold/profiles/industrial_default.tres`
- `core_v2/systems/scaffold/profiles/cryogenic_service.tres`
- `shaders/scaffold_far_parallax.shader`
- `core_v2/tests/test_infinite_scaffold_field.gd`
- `core_v2/tests/scaffold/test_scaffold_field.oys`

## Files to Modify

- `docs/features/FEATURE_INDEX.md` (add FD-037)
- `core_v2/systems/WorldRotator.gd` (optional, expose canonical transform helper if FD-036 has already implemented it)
- `core_v2/systems/GravityWorld.gd` (optional, expose ship axis / terrace shaft frame)
- Relevant level scenes that need exclusions, starting with the rotating terrace shaft test scene.

## Verification

1. Spawn `InfiniteScaffoldField` under `WorldRotator` and verify it rotates with terraces during FD-036 world rotation.
2. Move the player at least 100m through the field and verify cells recycle without visible popping near camera.
3. Place an exclusion volume around a terrace and verify no pipe intersects the excluded space, including soft-margin fade.
4. Confirm intersections appear approximately every 5m in canonical coordinates.
5. Confirm far LOD renders as cheap parallax/impostor layers, not individual pipe instances.
6. Run a stress scene with the player moving quickly and verify draw calls/node count remain bounded.
7. Run `./runtest.sh -a ./core_v2/tests/test_infinite_scaffold_field.gd`.
8. Before merge, run `./runtest.sh`.

## Open Questions

- El eje canonico definitivo del volumen debe venir de FD-036, `TerraceSpiral`, o una propiedad exportada local?
- El casco exterior ya existe como escena/mesh authorado, o FD-037 debe asumir `hull_radius` como parametro hasta que exista?
- Necesitamos colision navegable en partes del andamiaje, o esta feature es estrictamente visual para el MVP?
- El parallax lejano debe usar textura baked por perfil, shader procedural puro, o una combinacion?
