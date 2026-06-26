---
description: Crear, visualizar e iterar sobre el diseño visual de props de Odisea
---

# /odisea-prop — Crear e iterar props

Fuente canonica compartida: `docs/agents/tooling.md`.

## Flujo: Crear prop nuevo

1. Determinar el **tipo** (preguntar si no está claro):
   - `activable` — el jugador interactúa (hereda `InteractableBaseV2`)
   - `decorativo` — puramente visual, puede tener colisión estática
   - `ambiental` — parte del escenario, sin interacción

2. Crear `core_v2/props/<NombreProp>.gd` con la clase base correcta.

3. Crear `core_v2/props/<NombreProp>.tscn` con geometría CSG mínima.

4. Validar:
   ```bash
   ./test_prop.sh <NombreProp>
   ```

5. Leer el screenshot de `test_output/props/<NombreProp>_0_idle.png` y reportar.

## Flujo: Iterar diseño visual

```bash
./test_prop.sh <NombreProp>
# → leer screenshots de test_output/props/
# → editar core_v2/props/<NombreProp>.tscn
# → repetir
```

Para ver base64 en stdout:
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

### Decorativo (`StaticBody`)

```gdscript
extends StaticBody
```

### Ambiental (sin colisión)

Nodo raíz `Spatial`, solo geometría CSG hija.

## Materiales inline disponibles

| Material | Descripción |
|----------|-------------|
| Brushed steel claro | `metallic=1.0, roughness=0.18, albedo=Color(0.42,0.44,0.46)` |
| Brushed steel oscuro | `metallic=1.0, roughness=0.30, albedo=Color(0.30,0.32,0.34)` |
| Interactable cyan | `albedo=Color(0.15,0.80,0.78)` + `emission=Color(0,0.55,0.52)` |
| Advertencia amarilla | `albedo=Color(0.85,0.68,0.08), roughness=0.6` |
| Acero inoxidable | `res://materials/things/StainlessSteel.tres` |

## Gotchas

- **CSG subtract expone fondo blanco**: `operation = 2` con height ≥ mitad del padre atraviesa el objeto. Usar cajas aditivas encima (pads, ribs) en lugar de subtract.
- **`SlidingObjectV2` oculta `MeshInstance`**: nombrar la caja base exactamente `MeshInstance`; los `CSGBox` adicionales son seguros.
- **Metálico muy pulido = negro en el test**: `metallic=1.0, roughness<0.25` se ve negro en PropStage. En juego con luz real se ve correcto. No compensar bajando metallic.
- **Válvula fuera del encuadre**: si el interactable está en esquina alejada, crear `.oys` custom con `SPAWN` de `CameraClose.tscn`.
- **Props sin animación**: `test_prop.sh` falla delta check (<2%) si el prop no cambia visualmente. El exit code 0 indica screenshots generados; el warning de delta es esperado.
