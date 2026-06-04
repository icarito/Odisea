---
name: prop-visualizer
description: Crear, visualizar e iterar sobre el diseño visual de props de Odisea. Usar cuando se pida crear un nuevo prop, mejorar un prop existente, validar visualmente un prop, iterar sobre materiales o geometría de props, o generar archivos base para un prop.
---

Skill para crear y iterar props en `core_v2/props/`. Usa `./test_prop.sh` como
harness de visualización. Todos los paths son relativos a `src/`.

Ver FD: `docs/features/FD-051_prop_visualizer_skill.md`

## Flujo: Crear prop nuevo

Cuando el usuario pide crear un prop:

1. Determinar el **tipo** (preguntar si no está claro):
   - `activable` — el jugador interactúa con él (hereda `InteractableBaseV2`)
   - `decorativo` — puramente visual, puede tener colisión estática
   - `ambiental` — parte del escenario, sin interacción

2. Crear `core_v2/props/<NombreProp>.gd` con la clase base correcta (ver plantillas abajo)

3. Crear `core_v2/props/<NombreProp>.tscn` con geometría CSG mínima (ver plantillas abajo)

4. Validar inmediatamente:
   ```bash
   ./test_prop.sh <NombreProp>
   ```

5. Leer el screenshot de `test_output/props/<NombreProp>_0_idle.png` y reportar

## Flujo: Iterar diseño visual

Loop estándar para mejorar un prop existente:

```bash
./test_prop.sh <NombreProp>
# → leer screenshots de test_output/props/
# → editar core_v2/props/<NombreProp>.tscn
# → repetir
```

Para ver base64 en stdout (útil en contextos sin acceso a archivos locales):
```bash
./test_prop.sh <NombreProp> --base64
```

## Plantillas

### Activable (`InteractableBaseV2`)

**`<NombreProp>.gd`**:
```gdscript
extends InteractableBaseV2

func _update_visuals() -> void:
    # Interpolar visuales según anim_progress (0.0 = idle, 1.0 = active)
    pass
```

**`<NombreProp>.tscn`** (estructura mínima):
```
[gd_scene load_steps=3 format=2]

[ext_resource path="res://core_v2/props/<NombreProp>.gd" type="Script" id=1]

[sub_resource type="BoxShape" id=1]
extents = Vector3( 0.5, 0.5, 0.5 )

[node name="<NombreProp>" type="KinematicBody"]
script = ExtResource( 1 )
interaction_text = "Interact"

[node name="CollisionShape" type="CollisionShape" parent="."]
shape = SubResource( 1 )

[node name="MeshInstance" type="CSGBox" parent="."]
```

### Decorativo (`StaticBody`)

**`<NombreProp>.gd`**:
```gdscript
extends StaticBody
```

**`<NombreProp>.tscn`** (estructura mínima):
```
[gd_scene load_steps=3 format=2]

[sub_resource type="BoxShape" id=1]
extents = Vector3( 0.5, 0.5, 0.5 )

[node name="<NombreProp>" type="StaticBody"]

[node name="CollisionShape" type="CollisionShape" parent="."]
shape = SubResource( 1 )

[node name="MeshInstance" type="CSGBox" parent="."]
```

### Ambiental (sin colisión, solo visual)

```
[gd_scene load_steps=1 format=2]

[node name="<NombreProp>" type="Spatial"]

[node name="MeshInstance" type="CSGBox" parent="."]
```

## Materiales inline disponibles

Referenciar por path o definir inline como `[sub_resource type="SpatialMaterial"]`:

| Material | Path | Descripción |
|----------|------|-------------|
| Brushed steel claro | inline | `metallic=1.0, roughness=0.18, albedo=Color(0.42,0.44,0.46)` |
| Brushed steel oscuro | inline | `metallic=1.0, roughness=0.30, albedo=Color(0.30,0.32,0.34)` |
| Interactable cyan | inline | `albedo=Color(0.15,0.80,0.78)` + `emission=Color(0,0.55,0.52)` |
| Advertencia amarilla | inline | `albedo=Color(0.85,0.68,0.08), roughness=0.6` |
| Acero inoxidable | `res://materials/things/StainlessSteel.tres` | Metálico genérico |
| Suelo oscuro | `res://materials/interior/FloorDark.tres` | Para superficies de piso |

## Gotchas

- **CSG subtract expone fondo blanco**: Usar `operation = 2` en un hijo cuya height
  ≥ mitad del padre atraviesa el objeto. Para detalles de superficie usar cajas
  aditivas encima (pads, ribs) en lugar de subtract.

- **`SlidingObjectV2` y visibilidad de MeshInstance**: El script oculta el nodo
  `MeshInstance` si detecta otros `MeshInstance` hermanos. Nombrar la caja base
  exactamente `MeshInstance`; los detalles adicionales como `CSGBox` (subtipo de
  `Spatial`, no `MeshInstance`) son seguros como hermanos.

- **Metálico muy pulido = negro en el test**: `metallic=1.0, roughness<0.25` se
  ve negro en el ángulo rasante del PropStage. En juego con luz real se ve
  correcto. No compensar bajando metallic — verificar en editor si hay duda.

- **Válvula fuera del encuadre**: Si el interactable está en una esquina alejada
  del centro del prop, el PropStage no lo encuadrará. Crear un `.oys` custom con
  `SPAWN` de `CameraClose.tscn` para visualizarlo en test.

- **Props sin animación**: `test_prop.sh` falla el delta check (<2%) si el prop
  no cambia visualmente entre estados. Para decorativos esto es normal — el exit
  code 0 indica que los screenshots se generaron; el warning de delta es esperado.
