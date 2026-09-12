---
description: Modelado 3D programatico con Blender (bpy) headless — crear e iterar assets low-poly de Odisea con render de vista previa + export GLB
---

# /blender-bpy — Modelado programatico con Blender

Fuente canonica compartida: `docs/skills/blender-bpy.md`. Este archivo es el adaptador
de Kilo; las recetas, convenciones y scripts versionados viven en `docs/skills/blender-bpy/`.

## Loop iterativo

1. Escribir un *scene script* (Python con funcion `build()`) que construya la geometria.
2. Correr headless:
   ```bash
   blender --background --python docs/skills/blender-bpy/scripts/render.py -- \
     --scene <scene.py> --out assets/models/<Nombre> [--res 1024]
   ```
3. Adjuntar la vista previa al chat con `MEDIA:<out>/<Nombre>.png`.
4. Recibir feedback, editar el scene script, repetir.

## Reglas duras

- Godot 3.6 / GDScript 1.x. Nada de Godot 4.
- Un modelo a la vez; `read_factory_settings` limpia la escena en cada corrida.
- Paleta de materiales Odisea via `odisea_lib.py` (no inventar colores): ver
  `docs/skills/blender-bpy/references/conventions.md`.
- Validar orientacion `+Z = BACK` y escala tras importar a Godot.

## Detalle

- Recetas bpy: `docs/skills/blender-bpy/references/bpy-cheatsheet.md`.
- Convenciones y entorno del host: `docs/skills/blender-bpy/references/conventions.md`.
- Ejemplo: `docs/skills/blender-bpy/scripts/sample_scene.py`.
