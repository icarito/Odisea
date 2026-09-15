# FD-300 — Bake de lightmaps headless/programático en el fork de Godot

**Estado:** Propuesta
**Prioridad:** Alta (quita un paso 100% manual del pipeline de niveles)
**Repo objetivo:** `icarito/godot-box3d-3` (fork de Godot 3.6.4 + Box3D) — este FD se ejecuta ahí; este documento vive en `icarito/Odisea` solo como referencia del proyecto.

## Problema

Los niveles de Odisea (`Dome_Intro.tscn`, `Dome_Default.tscn`, hangar, etc.) usan
`BakedLightmap` con datos externos `.lmbake` y meshes `*_baked.mesh`. Los `.lmbake`
se versionan **sin datos** (git-friendliness), así que después de cualquier cambio
de geometría o luz hay que:

1. Abrir el editor de Godot.
2. Seleccionar cada `BakedLightmap`.
3. Clic en "Bake Lightmaps" (tarda minutos por nivel).
4. Verificar que los `.lmbake` quedaron con datos.

Ese paso es manual, no repetible en CI y bloquea la validación visual de PRs de
niveles (como el Dome Terrace V2 en curso).

## Objetivo

Exponer una forma **headless / programática** de ejecutar el bake de lightmaps en
el fork, sin abrir el editor interactivo:

```bash
# Propuesta de CLI (decidir forma final durante el spike)
godot.box3d.linux.x86_64.headless --path . --bake-lightmaps [opciones]
# o
godot.box3d... --path . -s res://tools/bake_lightmaps.gd  # si ya basta con scripting
```

Al terminar, desde Odisea se podrá correr:

```bash
G="$(bash tools/godot_bin.sh)"
"$G" --path . --no-window --bake-lightmaps --scene core_v2/levels/interiors/Dome_Intro.tscn
```

…y obtener los `.lmbake`/`*_baked.mesh` regenerados con exit code 0, o un error
claro (exit != 0) si el bake falla.

## Alcance (fork godot-box3d-3)

IN:
1. **Investigar primero (spike)**: en Godot 3.6, `BakedLightmap` expone
   `bake()` desde GDScript. Verificar si un script headless con
   `-s` puede: instanciar la escena, esperar un frame, llamar
   `bake_node.bake()`, guardar datos y salir con código. Si ya funciona con
   scripting puro, el "feature" puede reducirse a un **runner script + doc**, sin
   tocar C++.
2. Si `bake()` requiere contexto de editor (nodos internos no disponibles en
   headless), añadir el camino mínimo en C++ para que el bake funcione en
   `--no-window` (p. ej. exponer un `--bake-lightmaps` que recorra escenas y llame
   al mismo código del editor).
3. CLI mínima con:
   - `--scene <ruta>` (una escena o varias; sin flag = recorrer escenas que
     contengan `BakedLightmap`).
   - `--output-dir` opcional (default: junto a la escena, comportamiento actual).
   - Logs de progreso por escena + resumen final (`N escenas, M nodos baked`).
4. **Exit codes**: 0 = todos los bakes OK; 1 = fallo en uno o más (con el nombre
   de la escena/nodo en stderr).
5. Determinismo razonable: mismo input → mismos datos de bake (importante para
   no regenerar diffs ruidosos en git).
6. Test de verificación: escena mínima de prueba (cubo + DirectionalLight +
   BakedLightmap) incluida en el repo del fork o en Odisea, que el CI pueda
   ejecutar headless.

OUT (backlog):
- Denoising avanzado / calidad configurable por CLI (usar defaults del nodo).
- Bake en paralelo / distribuido.
- Soporte Godot 4.
- Integración con la UI del editor (no se toca la UI).

## Criterios de aceptación

1. En un checkout limpio de Odisea (con el binario del fork recién compilado o el
   nightly), correr el comando headless sobre `Dome_Intro.tscn` regenera
   `*.lmbake` válidos y termina con exit 0.
2. Si falta algún requisito (ej. escena sin UV2), el proceso falla con mensaje
   claro que nombre la escena y el nodo, exit 1.
3. Correrlo dos veces seguidas sin cambios produce datos idénticos (o diff
   explicable: timestamps fuera).
4. Documentado en el README del fork o `docs/` del fork: flags, ejemplos,
   limitaciones.
5. (Si hubo cambios C++) PR compilable en Linux x86_64; CI del fork en verde.

## Notas de implementación

- El proyecto Odisea ya tiene un patrón de runner headless:
  `tools/bake_dome_terrace_v2.gd` (script `-s` con `SceneTree`) y
  `tools/smoke_dome_default_v2.gd`. Reutilizar ese estilo para el runner.
- El binario que usamos en producción está en cache:
  `~/.cache/odisea-godot/v0.2.5/godot.box3d.linux.x86_64.headless` (fork
  `v3.6.4.rc.custom_build.6371881f6`). El CI de Odisea (`ci: pick up
  godot-box3d-3 v0.3.0` en main) ya descarga builds del fork.
- Godot 3: `BakedLightmap.bake(node_from, verbose)` devuelve `BakeError`.
  Los datos van a `light_data` y, si el nodo tiene path de datos externo, hay que
  persistirlo en disco (`.lmbake`) y regenerar el mesh bakeado si aplica —
  replicar exactamente lo que hace el botón del editor (buscar
  `BakedLightmap::bake` en `editor/` para el flujo completo).
- Cuidado con `OS.execute()` desde el propio Godot: el runner puede llamarse
  desde CI bash, no necesita self-exec.

## Referencias

- Nodos: `BakedLightmap` (`scene/3d/baked_lightmap.{h,cpp}` en el fork).
- Flujo editor: `editor/editor_node.cpp` → bake action de `BakedLightmap`.
- Uso actual en Odisea: grep `BakedLightmap` + `lmbake` en
  `icarito/Odisea` (`core_v2/levels/`).
