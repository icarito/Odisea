# FD-051: Prop Visualizer Skill

**Status:** In Progress
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-04

## Problem

El pipeline de validación visual de props (`test_prop.sh`) funciona bien para
verificar props ya creados, pero no guía la *creación* ni la *iteración de diseño*.
Un agente o desarrollador que quiere crear un nuevo prop necesita:

1. Saber qué clase base heredar según el tipo (interactable, decorativo, ambiental)
2. Generar los archivos mínimos correctos (`.tscn`, `.gd`, opcionalmente `.oys`)
3. Ver el resultado inmediatamente sin comandos ad hoc
4. Iterar sobre la geometría/materiales con feedback visual rápido

Además el concepto actual de "prop" asume elementos interactivos, pero muchos
props son decorativos o ambientales y no encajan en el flujo de `test_prop.sh`
(que espera estados idle/mid/active/off).

## Solution

Un skill `prop-visualizer` en `.claude/skills/prop-visualizer/` que:

### Flujo de creación de prop nuevo

```
/prop-visualizer create <NombreProp> [--type=activable|decorativo|ambiental]
```

1. Determina el tipo (pregunta si no se especifica)
2. Genera `core_v2/props/<NombreProp>.tscn` con plantilla según tipo
3. Genera `core_v2/props/<NombreProp>.gd` heredando de la clase base correcta
4. Opcionalmente genera `<NombreProp>.oys` para testing visual
5. Ejecuta `./test_prop.sh <NombreProp>` para primera validación
6. Muestra screenshots y sugiere próximos pasos

### Flujo de iteración visual

```
/prop-visualizer iterate <NombreProp>
```

1. Muestra estado actual (screenshots) con `./test_prop.sh <NombreProp>`
2. Sugiere cambios basándose en lo observado (materiales, geometría)
3. Aplica cambios al `.tscn`
4. Re-valida y muestra nuevo resultado
5. Repite hasta que el usuario apruebe

### Clases base por tipo

| Tipo | Clase base | OYS recomendado |
|------|-----------|-----------------|
| activable | `InteractableBaseV2` | Sí — estados idle/active |
| decorativo | `Spatial` o `StaticBody` | Opcional |
| ambiental | `Spatial` | No típicamente |
| procedural | `Spatial` + script custom | Depende |

### Plantillas de `.tscn`

**Activable** (hereda `InteractableBaseV2` via script):
```
[node name="<Nombre>" type="KinematicBody"]
script = ExtResource(1)  ; <Nombre>.gd

[node name="CollisionShape" type="CollisionShape" parent="."]
shape = SubResource(1)   ; BoxShape default

[node name="MeshInstance" type="CSGBox" parent="."]
; placeholder — reemplazar con mesh real
```

**Decorativo**:
```
[node name="<Nombre>" type="StaticBody"]

[node name="CollisionShape" type="CollisionShape" parent="."]
shape = SubResource(1)

[node name="MeshInstance" type="MeshInstance" parent="."]
```

**Ambiental** (sin colisión):
```
[node name="<Nombre>" type="Spatial"]

[node name="MeshInstance" type="MeshInstance" parent="."]
```

## Gotchas conocidos (descubiertos iterando sobre FloorHatch)

- **CSG subtract atraviesa toda la geometría**: Si se usa `operation = 2` en
  un CSGBox hijo con `height` igual o mayor a la mitad del padre, la sustracción
  atraviesa exponiendo el fondo del PropStage (blanco). Usar siempre geometría
  aditiva encima (pads, ribs) en lugar de subtract para detalle de superficie.

- **`SlidingObjectV2` oculta MeshInstance cuando hay hijos custom**: El script
  llama `_update_mesh_visibility()` que oculta el nodo `MeshInstance` si detecta
  otros `MeshInstance` o `Spatial` hermanos. Para puerta con detalles, nombrar
  la caja base exactamente `MeshInstance` y agregar detalles como hermanos CSGBox
  (que son `Spatial`, no `MeshInstance`) — así el nodo base permanece visible.

- **Materiales muy metálicos se ven negros en el ángulo rasante del PropStage**:
  `metallic=1.0, roughness<0.25` con luz ambiente baja da negro casi puro en
  la vista de prueba. En juego con iluminación real se ve correcto. No ajustar
  roughness para compensar el test — confiar en la preview del editor.

- **Válvula fuera del encuadre del PropStage**: Si la válvula está en una esquina
  del frame (ej. −1.5, 0, −1.5), el encuadre automático del PropStage no la
  muestra en idle. Normal — en juego se verá. Crear `.oys` custom con `SPAWN`
  de `CameraClose.tscn` si se necesita visualizar la válvula en test.

## Implementation Plan

### Fase 1 — Skill esqueleto (este FD)
- [x] Crear este FD
- [ ] Crear `.claude/skills/prop-visualizer/SKILL.md` con descripción e instrucciones
- [ ] Documentar plantillas en el skill

### Fase 2 — Flujo de creación
- [ ] Lógica de generación de `.tscn` por tipo (inline en SKILL.md como instrucciones
      para el agente, no como código ejecutable separado)
- [ ] Lógica de generación de `.gd` por tipo

### Fase 3 — Flujo de iteración visual
- [ ] Documentar el loop iterate: screenshot → análisis → edit → re-screenshot
- [ ] Casos especiales: prop sin animación (decorativo), prop con `.oys` custom

## Verification

1. Crear prop decorativo simple y verificar archivos generados en `core_v2/props/`
2. Crear prop activable y verificar que hereda `InteractableBaseV2` correctamente
3. `./test_prop.sh <NombreProp>` funciona (puede fallar con delta si es decorativo — OK)
4. Screenshots visibles y útiles para iterar diseño
