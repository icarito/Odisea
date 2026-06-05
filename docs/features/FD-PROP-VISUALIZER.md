# FD-PROP-VISUALIZER: Skill de Visualización y Feedback de Props

**Status:** Planned
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-04
**Completed:** -

## Problem

Los agentes de IA y desarrolladores necesitan una forma más intuitiva y rápida de crear, visualizar y obtener feedback sobre nuevos props en el juego Odisea. El pipeline actual de validación de props (`test_prop.sh`) es funcional pero requiere conocimiento específico de comandos y estructuras de archivos. Además, el concepto actual de "prop" asume principalmente elementos interactivos, pero muchos props son puramente decorativos, ambientales o procedimentales, lo que no se refleja bien en las herramientas actuales.

Se necesita un skill que:
1. Guíe al usuario (humano o agente IA) en la creación de nuevos props preguntando información relevante
2. Facilite la visualización inmediata de props en el editor de Godot
3. Genere los archivos básicos necesarios (escena, script, validator OYS opcional)
4. Proporcione feedback sobre si el prop cumple con los estándares del proyecto
5. Generalice el concepto de props más allá de lo meramente interactivo

## Solution

Crear un skill llamado `prop-visualizer` que ofrezca un flujo interactivo para:
- Preguntar por el nombre y tipo de prop (activable, decorativo, ambiental, procedural)
- Pedir una descripción corta del prop para documentación y contexto
- Generar automáticamente la estructura de archivos básica en `core_v2/props/`
- Crear una escena `.tscn` mínima con un nodo raíz apropiado según el tipo
- Generar un script GDScript básico heredando de la clase base correcta
- Opcionalmente crear un validator OYS para testing visual
- Abrir el prop en el editor de Godot para revisión inmediata (cuando esté disponible)
- Proporcionar comandos para validar el prop usando el pipeline existente (`test_prop.sh`)

### Considered Options

- **Option A**: Ampliar el script `test_prop.sh` para incluir modos de creación
  - Pros: Centraliza todo en un solo lugar, reutiliza lógica existente
  - Cons: Hace el script más complejo, menos enfocado en su propósito original (validación)
  - **Rechazado**: Mantener separación de preocupaciones

- **Option B**: Crear un skill independiente que orchestre la creación y use `test_prop.sh` para validación
  - Pros: Separación clara de responsabilidades, flujo interactivo guiado, reutiliza validation pipeline existente
  - Cons: Requiere mantener otro componente
  - **Seleccionado**: Mejor equilibrio entre funcionalidad y mantenibilidad

- **Option C**: Crear un plugin de editor de Godot para creación de props
  - Pros: Integrado directamente en el flujo de trabajo del editor
  - Cons: Solo útil cuando se tiene el editor abierto, no accesible para agentes IA sin GUI, mayor esfuerzo de desarrollo
  - **Rechazado**: No sirve para el flujo de trabajo basado en terminal/agentes que actualmente usamos

## Files to Modify

- `skills/props/SKILL.md` (new)
- `skills/props/bin/prop-visualizer` (new, script principal)
- `skills/props/templates/` (new, plantillas para archivos generados)
  - `templates/prop_tscn.j2`
  - `templates/prop_gd.j2`
  - `templates/prop_oys.j2` (opcional)
  - `templates/prop_metadata.j2` (para documentación interna)

## Verification

1. **Creación básica**: Ejecutar el skill para crear un prop decorativo simple y verificar que se generan los archivos correctos en `core_v2/props/`
2. **Plantillas aplicadas**: Verificar que las plantillas se renderizan correctamente con los parámetros proporcionados
3. **Integración con validation**: Confirmar que `./test_prop.sh --target="<Nombre>"` funciona en el prop recién creado (aunque pueda fallar inicialmente por falta de animación, debería encontrar los archivos)
4. **Feedback al usuario**: Verificar que el skill proporciona mensajes claros sobre lo que creó y próximos pasos sugeridos
5. **Manejo de errores**: Probar casos como nombre duplicado, tipo inválido, directorio de destino no escribible
6. **Documentación**: Verificar que SKILL.md explica claramente el uso y opciones disponibles

## Detalles de Implementación

### Flujo de trabajo del skill

1. **Inicio**: El skill se invoca con `prop-visualizer create` (o similar)
2. **Preguntas interactivas**:
   - Nombre del prop (requerido, snake_case sugerido)
   - Tipo de prop: [activable] [decorativo] [ambiental] [procedural]
   - Descripción corta del prop (para documentación y contexto)
   - ¿Crear validator OYS básico? [sí/no]
   - ¿Abrir en editor de Godot después de crear? [sí/no] (solo si se detecta entorno GUI)
3. **Generación de archivos**:
   - Crea `core_v2/props/<Nombre>.tscn` usando plantilla apropiada según tipo
   - Crea `core_v2/props/<Nombre>.gd` heredando de clase base correcta
   - Si se solicita, crea `core_v2/props/<Nombre>.oys` con validator básico
   - Opcional: crea documento de metadata interna
4. **Salida**:
   - Lista de archivos creados
   - Comandos sugeridos para validar: `./test_prop.sh --target="<Nombre>" --base64`
   - Si se solicitó abrir en editor: instrucciones o intento de abrir
5. **Tipos de props y sus características**:
   - **Activable**: Hereda de `InteractableBaseV2`, requiere `_update_visuals()`, validator OYS recomendado
   - **Decorativo**: Hereda de `Node3D` o `StaticBody3D`, principalmente visual, puede tener animaciones ambientales
   - **Ambiental**: Parte del escenario, puede afectar iluminación o audio, generalmente estático
   - **Procedural**: Generado dinámicamente, puede usar mesh instantiation o herramientas de WFC

### Plantillas básicas

**Plantilla TSNC para prop activable**:
```tscn
[gd_scene load_steps=3 format=3 uid="UID_GENERADO"]
[ext_resource type="Script" path="res://core_v2/props/{{nombre}}.gd" id=1]
[node name="Prop{{nombre}}" type="InteractableBaseV2"]
script = ExtResource( 1 )
```

**Plantilla GDScript para prop activable**:
```gdscript
extends "res://core_v2/components/interactable_base_v2.gd"

# {{nombre}} - Prop {{tipo}}
# Descripción: {{descripcion}}

# Señales
# signal ejemplo_signal

# Variables exportadas
# @export var velocidad_animacion: float = 1.0

# Estado interno
var anim_progress: float = 0.0
setget set_anim_progress

func _ready() -> void:
    pass

func _update_visuals() -> void:
    # Actualizar visuales basado en anim_progress [0.0, 1.0]
    # Ejemplo: $MeshInstance3D.scale = Vector3.ONE * lerp(0.5, 1.5, anim_progress)
    pass

func set_anim_progress(value: float) -> void:
    anim_progress = value
    _update_visuals()
```

**Plantilla TSNC para prop decorativo**:
```tscn
[gd_scene load_steps=3 format=3 uid="UID_GENERADO"]
[ext_resource type="Script" path="res://core_v2/props/{{nombre}}.gd" id=1]
[node name="Prop{{nombre}}" type="StaticBody3D"]
script = ExtResource( 1 )
```

**Plantilla GDScript para prop decorativo**:
```gdscript
extends "res://core_v2/components/static_body_v2.gd"

# {{nombre}} - Prop {{tipo}}
# Descripción: {{descripcion}}

# Variables exportadas
# @export var animacion_ambiental: bool = false
# @export var velocidad_rotacion: float = 0.5

func _ready() -> void:
    pass

func _process(delta: float) -> void:
    if animacion_ambiental:
        rotate_y(deg2rad(velocidad_rotacion * delta))
```

### Integración con flujo existente

El skill no reemplaza ni modifica el pipeline de validation existente (`test_prop.sh`). En cambio, lo complementa al hacer más fácil crear props que luego pueden ser validados usando las herramientas actuales.

Después de crear un prop con el skill, el usuario/agente debería:
1. Implementar la lógica específica del prop en el GDScript
2. Ejecutar `./test_prop.sh --target="<Nombre>" --base64` para validar visualmente
3. Iterar hasta que la validación pase (o ajustar thresholds según sea necesario)
