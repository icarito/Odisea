# Recetas bpy — Blender 4.3 (Python API)

Referencia rápida de patrones verificados en este entorno (Blender 4.3.2, CPU).

## Estructura de un scene script

```python
import bpy, math
import sys
sys.path.insert(0, "docs/skills/blender-bpy/scripts")
from odisea_lib import mat_brushed_steel_light, apply_mat

NAME = "MiModelo"   # opcional: nombre base para <NAME>.png / <NAME>.glb

def build():
    # geometría aquí; la escena ya está limpia, con cámara y sol
    pass
```

El runner ya hace `read_factory_settings`, agrega cámara + sol, y renderiza/exporta.
Si el script quiere cámara/luz propias, definir `SELF_CAMERA = True` / `SELF_LIGHT = True`.

## Primitivas

```python
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
obj = bpy.context.active_object
obj.name = "Body"
```

## Material simple (Principled BSDF)

```python
mat = bpy.data.materials.new("M_X")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.4, 0.4, 0.4, 1.0)
bsdf.inputs["Metallic"].default_value = 1.0
bsdf.inputs["Roughness"].default_value = 0.3
obj.data.materials.append(mat)
```

## Transform

```python
obj.location = (1, 2, 0)
obj.rotation_euler = (0, 0, math.radians(45))
obj.scale = (1, 1, 2)
```

## Modificador boolean (huecos)

```python
m = obj.modifiers.new("Cut", "BOOLEAN")
m.operation = "DIFFERENCE"
m.object = cutter_obj
bpy.ops.object.modifier_apply(modifier="Cut")
```

## Rigging (armature)

```python
arm_data = bpy.data.armatures.new("Rig")
arm_obj = bpy.data.objects.new("WalkerRig", arm_data)
bpy.context.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="EDIT")
for i, (head, tail) in enumerate([((0,0,0),(0,0,1)), ((0,0,1),(0,0,2))]):
    b = arm_data.edit_bones.new(f"Bone_{i}")
    b.head, b.tail = head, tail
    if i > 0:
        b.parent = arm_data.edit_bones[f"Bone_{i-1}"]
bpy.ops.object.mode_set(mode="OBJECT")
```

## Walk cycle procedural (sine sobre cadena de huesos)

```python
import math
scene = bpy.context.scene
frames = 60
for f in range(frames):
    scene.frame_set(f)
    for i, bone_name in enumerate(["Spine1", "Spine2", "Spine3"]):
        bone = arm_obj.pose.bones[bone_name]
        bone.rotation_euler.z = math.sin(f / frames * 2 * math.pi * 2 + i) * 0.3
        bone.keyframe_insert(data_path="rotation_euler", frame=f)
```

## Keyframes de objeto

```python
obj.keyframe_insert(data_path="location", frame=0)
obj.location.x = 2
obj.keyframe_insert(data_path="location", frame=30)
```

## Export GLB (animado)

```python
bpy.ops.export_scene.gltf(
    filepath="/tmp/out.glb",
    export_format="GLB",
    export_apply=False,        # NO aplicar transforms a rigs
    export_animations=True,
)
```

## Render a PNG

```python
bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
bpy.context.scene.render.resolution_x = 1024
bpy.context.scene.render.resolution_y = 1024
bpy.context.scene.render.filepath = "/tmp/preview.png"
bpy.ops.render.render(write_still=True)
```

## Enums que cambiaron en Blender 4.x

- `BLENDER_EEVEE` → `BLENDER_EEVEE_NEXT` (EEVEE clásico desapareció).
- Otros enums: consultar con `bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items`.

## Verificación rápida headless

```bash
blender --background --python-expr "import numpy; print(numpy.__version__)"
```
