# FD-043: RadialScatter Tool Node

**Status:** Implemented
**Priority:** Medium
**Effort:** Small
**Created:** 2026-05-29
**Completed:** 2026-05-29

## Problem

Poblar un domo con props repetibles (CriopodParallax, pilares, luces) requiere
instanciar manualmente N copias, posicionarlas en circulo y orientarlas hacia
el centro. Es tedioso y dificil de iterar. Se necesita un tool node que
automatice la disposicion radial con control fino de orientacion.

## Solution

Tool script RadialScatter.gd que extiende Spatial y genera N instancias de una
PackedScene en un arreglo radial alrededor del origen.

### Exports

| Parametro | Tipo | Default | Descripcion |
|-----------|------|---------|-------------|
| target_scene | PackedScene | null | Escena a instanciar |
| item_count | int | 8 | Numero de instancias (1-64) |
| radius | float | 5.0 | Distancia desde el centro |
| height_offset | float | 0.0 | Desplazamiento en Y |
| inward | bool | true | true = mira al centro |
| rotation_x/y/z | float | 0.0 | Rotacion relativa adicional |
| randomize_rotation | bool | false | Offset aleatorio en Y |
| rand_rotation_amount | float | 15.0 | Rango del offset aleatorio |
| auto_build | bool | true | Reconstruye al cambiar exports |

### Algoritmo

```
para i in 0..item_count:
  angle = (i / item_count) * TAU
  pos = Vector3(cos(angle)*radius, height_offset, sin(angle)*radius)
  instance = target_scene.instance()
  instance.transform.origin = pos
  si inward: instance.look_at(Vector3(0, height_offset, 0), UP)
  aplicar rotation_x/y/z adicional
  add_child(instance)
```

### Comportamiento en editor

- Tool script, se ejecuta en el editor.
- Si auto_build es true, rebuild al cambiar exports en el Inspector.
- Cada instancia se nombra "Item_0", "Item_1", etc.
- Si target_scene es null, logea warning y no hace nada.

## Fase 2 — Batch to MultiMesh (no implementado)

En una segunda fase, se agregara un boton "Batch to MultiMesh" que:

1. Recolecta todas las instancias hijas.
2. Extrae sus meshes y transforms.
3. Las fusiona en un MultiMeshInstance para optimizar draw calls.
4. Elimina las instancias originales.

El boton queda como placeholder en el script para implementacion futura cuando
el rendimiento lo requiera.

## Files Created

- `core_v2/tools/RadialScatter.gd`

## Verification

1. Crear un Spatial, asignarle RadialScatter.gd.
2. Asignar CriopodParallax.tscn como target_scene.
3. Ajustar item_count=12, radius=6.0, rotation_x=-15.
4. Confirmar que las 12 instancias aparecen en circulo mirando al centro.
5. Cambiar item_count a 6 — las instancias se redistribuyen.
6. Probar randomize_rotation para variedad visual.
