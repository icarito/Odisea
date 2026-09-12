# blender-bpy — Modelado 3D programático para Odisea

Workflow canónico para crear e iterar assets 3D de Odisea usando la API Python de
Blender (`bpy`), con feedback visual por chat. Aplica a cualquier agente (Odiseo,
Claude en VSCode, etc.). El adaptador Claude (shim local, no versionado) vive en
`.claude/skills/blender-bpy/SKILL.md`.

## Cuándo usar

- Crear props, modelos o criaturas low-poly desde cero (sin piratear Sketchfab).
- Riggear y animar de forma repetible (walk cycles, ciclos mecánicos, bobinas).
- Iterar geometría/materiales con capturas de vista previa y feedback humano.

## Pipeline (loop iterativo)

1. Escribir un *scene script* (Python que define una función `build()` y construye geometría).
2. Correr headless: render de vista previa PNG + export GLB.
3. Adjuntar la imagen al chat (`MEDIA:<ruta>`), recibir feedback.
4. Ajustar el scene script y repetir. Un modelo a la vez; limpiar entre modelos.

## Comando

```bash
blender --background --python docs/skills/blender-bpy/scripts/render.py -- \
  --scene <scene.py> --out assets/models/<Nombre> [--res 1024] [--no-glb]
```

El runner hace: `read_factory_settings` (escena limpia), carga el scene script, agrega
cámara + sol si faltan, renderiza `<Nombre>.png` y exporta `<Nombre>.glb`.
El runner inserta su propio directorio en `sys.path`, así que los scene scripts hacen
`from odisea_lib import ...` directamente.

## Convenciones Odisea (obligatorias)

- Target **Godot 3.6 / GDScript 1.x**. Nunca asumir Godot 4.
- Formato de import: `.glb` en `assets/models/<Nombre>/`.
- Low-poly sci-fi. Paleta de materiales en `references/conventions.md`.
- Coordenadas Godot: `+Z = BACK`, `-Z = FORWARD`. Validar orientación tras importar.
- Para props que van a `core_v2/props/`, respetar autoría → horneado determinista
  (`tools/bake_*.gd`), no meter `.glb` crudo como fuente de runtime.

## Detalle

- Recetas bpy (geometría, boolean, rig, walk cycle, export): `references/bpy-cheatsheet.md`.
- Convenciones (materiales, escala, naming, Godot 3): `references/conventions.md`.
- Entorno del host (Blender 4.3.2, CPU-only, numpy): `references/conventions.md`.
- Ejemplo completo: `scripts/sample_scene.py` (válvula con volante cian).
