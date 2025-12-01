# Odisea: Guía de Desarrollo Técnico del MVP
## Godot 3.x / GLES2 | Investigación Exhaustiva & Pipeline Específico

**Versión:** 1.0 | **Fecha:** 2025-12-01  
**Estado del Proyecto:** Godot 3.6.x, KinematicBody 3D, AnimationTree implementado  
**Objetivo MVP:** Acto I (Criogenia + Mantenimiento) con mecánicas base satisfactorias

---

## Tabla de Contenidos

1. [Agenda de Investigación Priorizada](#1-agenda-de-investigación-priorizada)
2. [Sistema 1: Transferencia de Velocidad de Plataforma](#2-transferencia-de-velocidad-de-plataforma)
3. [Sistema 2: Trayectorias Curvilíneas (Path + PathFollow)](#3-trayectorias-curvilíneas-path--pathfollow)
4. [Sistema 3: Perfiles de Aceleración y Feel](#4-perfiles-de-aceleración-y-feel)
5. [Sistema 4: Coyote Time e Input Buffering](#5-coyote-time-e-input-buffering)
6. [Sistema 5: Cámara Spring-Damper](#6-cámara-spring-damper)
7. [Sistema 6: Conveyor Consistente](#7-conveyor-consistente)
8. [Sistema 7: FSM Simple para Enemigos DDC](#8-fsm-simple-para-enemigos-ddc)
9. [Sistema 8: Visión Cónica y Detección de Sigilo](#9-visión-cónica-y-detección-de-sigilo)
10. [Sistema 9: Diálogos y Narrativa (JSON + AudioStreamPlayer3D)](#10-diálogos-y-narrativa-json--audiostreamplayer3d)
11. [Artefactos y Herramientas de Desarrollo](#11-artefactos-y-herramientas-de-desarrollo)
12. [Cronograma de Implementación Sugerido](#12-cronograma-de-implementación-sugerido)

---

## 1. Agenda de Investigación Priorizada

### Ranking por Impacto en MVP

| Prioridad | Sistema | Impacto | Complejidad | Refs |
|-----------|---------|--------|-------------|------|
| **CRÍTICA** | Plataforma + Snap | Jugabilidad base | Media | [web:16][web:17][web:25] |
| **CRÍTICA** | Coyote Time | Feel del juego | Baja | [web:18][web:21][web:24] |
| **CRÍTICA** | Diálogos JSON | Narrativa Acto I | Baja | [web:88][web:91][web:94] |
| **ALTA** | PathFollow curvas | Futuro Acto II | Alta | [web:33][web:41] |
| **ALTA** | Conveyor | Puzzle Criogenia | Media | [web:60][web:66] |
| **MEDIA** | FSM Enemigos | Sigilo Acto I | Media | [web:61][web:64][web:67] |
| **MEDIA** | Cámara Spring-Damper | Lectura clara | Media | [web:35][web:37][web:40] |
| **MEDIA** | Visión Cónica | Sistema anti-alerta | Media | [web:62][web:65][web:68] |
| **BAJA** | Aceleración Curves | Pulido final | Baja | [web:36][web:39][web:34] |

---

## 2. Transferencia de Velocidad de Plataforma

### El Problema (de tu GDD)

Tu `MovingPlatform.gd` actual mueve una plataforma A↔B pero **no comunica su velocidad** al jugador.  
Resultado: Elías se queda atrás, jitter, deslizamiento incómodo.

### Solución: Interfaz de Velocidad Externa

#### 2.1 Modificar `PlayerController.gd`

```gdscript
# players/elias/PlayerController.gd (KinematicBody)

# =====  NUEVAS VARIABLES =====
var platform_velocity := Vector3.ZERO
var snap_len := 0.5  # Distancia de búsqueda de snap (metros)
var snap_enabled := true

# =====  NUEVA FUNCIÓN =====
func set_external_velocity(v: Vector3) -> void:
    """
    Llamada por plataformas/conveyor para aplicar velocidad externa.
    La velocidad se integra cada frame y decae gradualmente.
    """
    platform_velocity = v

# =====  MODIFICAR _physics_process =====
func _physics_process(delta):
    # ... código existente de input ...
    var desired_horizontal = get_input_direction()
    
    # Interpolación suave de aceleración (CÓDIGO EXISTENTE)
    horizontal_velocity = horizontal_velocity.linear_interpolate(
        desired_horizontal * max_speed,
        acceleration * delta
    )
    
    # ===== NUEVA LÓGICA: VELOCIDAD EXTERNA =====
    var hv := horizontal_velocity
    hv += platform_velocity  # <-- AQUÍ agregamos la velocidad de la plataforma
    
    # Aplicar gravedad (CÓDIGO EXISTENTE)
    vertical_velocity.y += gravity * delta
    
    # ===== SNAP MEJORADO =====
    var on_floor := is_on_floor()
    var snap_vec := Vector3.ZERO
    
    if on_floor and snap_enabled:
        snap_vec = -get_floor_normal() * snap_len
    
    # Construir vector de movimiento
    var motion := Vector3(hv.x, vertical_velocity.y, hv.z)
    
    # Usar move_and_slide_with_snap (CRÍTICO para plataformas)
    motion = move_and_slide_with_snap(motion, snap_vec, Vector3.UP, true)
    
    # Actualizar velocidades
    horizontal_velocity = Vector3(motion.x, 0, motion.z)
    vertical_velocity.y = motion.y
    
    # ===== DECAIMIENTO DE VELOCIDAD EXTERNA =====
    # Interpolar desde platform_velocity hacia 0 en este frame
    # Esto evita que la velocidad "pegue" al jugador múltiples frames
    platform_velocity = platform_velocity.linear_interpolate(
        Vector3.ZERO,
        clamp(6.0 * delta, 0.0, 1.0)  # Factor de decaimiento
    )
    
    # ... resto del código (animaciones, rotaciones, etc.) ...
```

**Notas importantes:**

- El factor `6.0` en el decaimiento es experimental; ajusta según "feel" deseado.
- `snap_len = 0.5` es típico para plataformas; aumenta si necesitas más tolerancia.
- **Deshabilitar `stop_on_slope`** en KinematicBody inspector (provoca bugs con plataformas).

#### 2.2 Modificar `MovingPlatform.gd`

```gdscript
# scenes/common/MovingPlatform.gd (Spatial)

extends Spatial

export var point_a := Vector3(0, 0, 0)
export var point_b := Vector3(5, 0, 0)
export var speed := 2.0  # unidades por segundo
export var wait_time := 1.0
export var easing := "Linear"  # "EaseIn", "EaseOut", "EaseInOut", etc.

var current_target := point_b
var is_waiting := false
var wait_timer := 0.0
var last_position := Vector3.ZERO
var platform_bodies := []  # Cuerpos sobre la plataforma

func _ready():
    last_position = global_transform.origin

func _physics_process(delta):
    # Movimiento (CÓDIGO EXISTENTE)
    if not is_waiting:
        var direction = (current_target - global_transform.origin).normalized()
        var distance = global_transform.origin.distance_to(current_target)
        
        if distance < speed * delta:
            global_transform.origin = current_target
            is_waiting = true
            wait_timer = 0.0
            current_target = point_a if current_target == point_b else point_b
        else:
            global_transform.origin += direction * speed * delta
    else:
        wait_timer += delta
        if wait_timer >= wait_time:
            is_waiting = false
    
    # ===== NUEVA LÓGICA: COMUNICAR VELOCIDAD =====
    var current_position = global_transform.origin
    var velocity = (current_position - last_position) / delta
    last_position = current_position
    
    # Notificar a todos los cuerpos sobre la plataforma
    for body in platform_bodies:
        if body.has_method("set_external_velocity"):
            body.set_external_velocity(velocity)

# ===== DETECTAR CUERPOS SOBRE LA PLATAFORMA =====
func _on_PlatformArea_body_entered(body):
    """Conectar esta función a la señal body_entered del Area3D."""
    if not platform_bodies.has(body):
        platform_bodies.append(body)

func _on_PlatformArea_body_exited(body):
    """Conectar esta función a la señal body_exited del Area3D."""
    platform_bodies.erase(body)
```

**Estructura de escena esperada (MovingPlatform.tscn):**

```
MovingPlatform (Spatial) [script: MovingPlatform.gd]
├── MeshInstance (plataforma visible)
├── CollisionShape3D (colisión estática)
├── Area3D (detección de pasajeros)
│   ├── CollisionShape3D (mismo tamaño que plataforma)
```

#### 2.3 Configuración en Editor

1. Abre `criogenia.tscn`
2. Selecciona `MovingPlatform_B` (o crea una nueva)
3. Asigna `point_a` y `point_b` en inspector
4. Conecta señales de `Area3D`:
   - `body_entered` → `_on_PlatformArea_body_entered`
   - `body_exited` → `_on_PlatformArea_body_exited`

#### 2.4 Pruebas

**Escena de sandbox (`test_platform_linear.tscn`):**

```gdscript
# En PlayerController debug:
print("Platform velocity: %.2f m/s" % platform_velocity.length())
print("Player velocity: %.2f m/s" % horizontal_velocity.length())
```

**Esperado:**
- Elías se mueve CON la plataforma sin jitter.
- Velocidad de Elías = velocidad de la plataforma mientras está sobre ella.
- Al saltar DESDE la plataforma, Elías retiene parte de la velocidad.

### Referencias Documentadas

- **[web:16]** GitHub Issue: Problemas con `move_and_slide_with_snap` en plataformas móviles  
  → Explicación de `stop_on_slope` bug
- **[web:17]** YouTube: "How to Create Perfect Moving Platforms in Godot 3.1" (2019)  
  → Demostración de snap correcto
- **[web:25]** kidscancode: Moving Platforms Recipe  
  → Ejemplo de animación con `move_and_slide_with_snap`
- **[web:20]** Reddit: "Adding platform velocity to player when jumping"  
  → Discusión de cómo integrar `get_platform_velocity()`

---

## 3. Trayectorias Curvilíneas (Path + PathFollow)

### Contexto MVP

Para el **Acto I (Criogenia)**, las plataformas son lineales (A↔B).  
Pero este sistema preparará el camino para:

- **Acto II**: Bio-Granjas con módulos rotatorios → curvas complejas.
- **Acto III**: Núcleo 0G → trayectorias 3D tridimensionales.

### Arquitectura: Path3D + PathFollow3D + Curve1D

#### 3.1 Crear `MovingPlatform_Curved.tscn`

```
MovingPlatform_Curved (Spatial)
├── Path3D (define la curva)
│   ├── Curve3D (recurso, editable en el gizmo)
│   └── PathFollow3D (sigue la curva)
│       ├── MeshInstance (plataforma visible)
│       └── CollisionShape3D
├── Area3D (detección de pasajeros)
├── [script: MovingPlatform_Curved.gd]
```

#### 3.2 Implementar `MovingPlatform_Curved.gd`

```gdscript
# scenes/common/MovingPlatform_Curved.gd (Spatial)

extends Spatial

# ===== REFERENCIAS =====
export var path_node_path: NodePath
export var speed := 2.0  # unidades por segundo
export var loop := true
export var ease_curve: Curve  # Curve1D para temporal easing (opcional)

var path_follow: PathFollow3D
var last_position := Vector3.ZERO
var time_along_path := 0.0  # [0, 1]
var total_curve_length := 0.0
var platform_bodies := []

func _ready():
    # Obtener referencias
    var path = get_node(path_node_path)
    path_follow = path.get_child(0) if path.get_child_count() > 0 else null
    
    if not path_follow or not path_follow is PathFollow3D:
        push_error("MovingPlatform_Curved: No PathFollow3D encontrado")
        return
    
    # Calcular longitud total de la curva para velocidad consistente
    var curve = path.curve
    if curve:
        total_curve_length = curve.get_baked_length()
    
    last_position = global_transform.origin
    
    # Conectar Area3D de pasajeros
    if has_node("Area3D"):
        var area = get_node("Area3D")
        area.connect("body_entered", self, "_on_Area_body_entered")
        area.connect("body_exited", self, "_on_Area_body_exited")

func _physics_process(delta):
    if not path_follow:
        return
    
    # ===== ACTUALIZAR POSICIÓN SOBRE LA CURVA =====
    # Velocidad lineal normalizada al rango [0, 1]
    var distance_per_frame = speed * delta
    var unit_offset_increment = distance_per_frame / (total_curve_length + 0.001)
    
    time_along_path += unit_offset_increment
    
    if loop:
        time_along_path = fmod(time_along_path, 1.0)
    else:
        time_along_path = clamp(time_along_path, 0.0, 1.0)
    
    # ===== APLICAR EASING TEMPORAL (OPCIONAL) =====
    var eased_t = time_along_path
    if ease_curve:
        eased_t = ease_curve.interpolate_baked(time_along_path)
    
    # Mover PathFollow
    path_follow.unit_offset = eased_t
    
    # ===== CALCULAR VELOCIDAD INSTANTÁNEA =====
    var current_position = path_follow.global_transform.origin
    var velocity = (current_position - last_position) / delta
    last_position = current_position
    
    # ===== COMUNICAR A PASAJEROS =====
    for body in platform_bodies:
        if body.has_method("set_external_velocity"):
            body.set_external_velocity(velocity)

func _on_Area_body_entered(body):
    if not platform_bodies.has(body):
        platform_bodies.append(body)

func _on_Area_body_exited(body):
    platform_bodies.erase(body)
```

#### 3.3 Crear la Curva en Editor

1. **Crear Path3D:**
   - Instancia Path3D como nodo dentro de MovingPlatform_Curved
   - En el inspector, haz clic en `Curve3D` para expandir
   - Dibuja puntos en el 3D viewport (Shift + Click en el Path3D)

2. **Editar Curve3D:**
   ```
   Editor 3D → Path3D seleccionado → Gizmo de edición
   - Arrastra puntos para posicionarlos
   - Ajusta handles de entrada/salida para suavidad
   - Aumenta densidad si necesitas más resolución
   ```

3. **Crear Curve (easing temporal):**
   - Clic derecho en carpeta `data/` → New Resource → Curve
   - Nombre: `curve_ease_inout.tres`
   - Selecciona preset "EaseInOut"
   - Guarda

4. **Asignar en MovingPlatform_Curved:**
   - Selecciona nodo
   - Inspector → path_node_path = "Path3D"
   - ease_curve = `res://data/curve_ease_inout.tres`

#### 3.4 Ventajas para tu Proyecto

- **Futuro Acto II**: Las Bio-Granjas con módulos rotatorios pueden usar PathFollow en órbita.
- **Mantenibilidad**: No necesitas código Bezier manual.
- **Iteración rápida**: Edita curvas en el editor sin tocar código.

### Referencias Documentadas

- **[web:33]** YouTube: "How to follow a path in Godot" (2024, Godot 4 pero similar en 3)  
  → Explica Path3D + PathFollow3D en profundidad
- **[web:41]** YouTube: "Path Follow Platforms for Better Level Design" (2022)  
  → Patrón específico para plataformas curvas
- **[web:36]** YouTube: "How to make better games using Curves in Godot" (2019)  
  → Uso de Curve1D para easing temporal

---

## 4. Perfiles de Aceleración y Feel

### El Desafío

Tu `PlayerController.gd` usa interpolación lineal simple para aceleración.  
Resultado percibido: Movimiento "mecánico", cambios de velocidad abruptos.

### Solución: Curve1D para Aceleración

#### 4.1 Crear Curvas de Aceleración

En `data/acceleration_profiles.tres` (o carpeta separada):

```gdscript
# Crear manualmente en editor o con este script EditorScript:
extends EditorScript

func _run():
    # Curve para aceleración "snappy" (Mario-like)
    var curve_snappy = Curve.new()
    curve_snappy.add_point(Vector2(0, 0))
    curve_snappy.add_point(Vector2(0.3, 0.9))  # Rápido al inicio
    curve_snappy.add_point(Vector2(1.0, 1.0))
    var saved = curve_snappy.resource_path or "res://data/accel_snappy.tres"
    ResourceSaver.save(saved, curve_snappy)
    
    # Curve para aceleración "smooth" (Slow start, smooth middle)
    var curve_smooth = Curve.new()
    curve_smooth.add_point(Vector2(0, 0))
    curve_smooth.add_point(Vector2(0.5, 0.4))  # Suave
    curve_smooth.add_point(Vector2(1.0, 1.0))
    saved = curve_smooth.resource_path or "res://data/accel_smooth.tres"
    ResourceSaver.save(saved, curve_smooth)
    
    print("Curves created successfully")
```

#### 4.2 Integrar en PlayerController.gd

```gdscript
# players/elias/PlayerController.gd

# ===== NUEVAS VARIABLES =====
export var acceleration_curve: Curve  # Asignar en editor
export var acceleration_time := 0.3  # Tiempo para alcanzar max_speed
var acceleration_timer := 0.0
var target_horizontal_velocity := Vector3.ZERO

func _physics_process(delta):
    # ... obtener input ...
    var desired_direction = get_input_direction()
    target_horizontal_velocity = desired_direction * max_speed
    
    # ===== ACELERACIÓN CON CURVE =====
    if acceleration_curve and target_horizontal_velocity.length() > 0.01:
        acceleration_timer = min(acceleration_timer + delta, acceleration_time)
        var t = acceleration_timer / acceleration_time
        var curve_factor = acceleration_curve.interpolate_baked(t)
        horizontal_velocity = horizontal_velocity.lerp(
            target_horizontal_velocity,
            curve_factor
        )
    elif target_horizontal_velocity.length() < 0.01:
        # Decaimiento rápido cuando sueltas input
        horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, 0.1)
        acceleration_timer = 0.0
    
    # ... resto del movimiento ...
```

#### 4.3 Resultados Esperados

- **Snappy**: Arranques rápidos, sensación Mario 64.
- **Smooth**: Arranques graduales, sensación más "pesada" (como Elías en gravedad parcial).

Para Odisea Acto I (traje de mantenimiento), **recomendación: Smooth con pequeño spike**.

### Referencias Documentadas

- **[web:36]** YouTube: "How to make better games using Curves in Godot" (2019)  
  → Demostración visual de Curve y su impacto
- **[web:39]** Forum Godot: "How to properly use Curve resource for interpolating movement"  
  → Ejemplos con `move_toward()` + Curve
- **[web:34]** YouTube: "Godot Engine 3 - Platformer Game Tutorial P3 - Smooth Character Movement"  
  → Implementación de acceleration/friction sin Curve (baseline)

---

## 5. Coyote Time e Input Buffering

### Problema

Sin coyote time: Saltamos justo después de caer de una plataforma → frustración.  
Sin input buffering: Presionamos salto 100ms antes de aterrizar → no salta.

### Solución: Timers Simples

#### 5.1 Implementar en PlayerController.gd

```gdscript
# players/elias/PlayerController.gd

# ===== COYOTE TIME & INPUT BUFFERING =====
export var coyote_time := 0.12  # 120ms (típico)
export var jump_buffer_time := 0.1  # 100ms

var coyote_timer := 0.0
var can_coyote_jump := false
var jump_buffer_timer := 0.0
var should_jump_buffered := false

func _physics_process(delta):
    # ===== COYOTE TIME =====
    if is_on_floor():
        coyote_timer = coyote_time
        can_coyote_jump = true
    else:
        coyote_timer -= delta
        if coyote_timer <= 0.0:
            can_coyote_jump = false
    
    # ===== INPUT BUFFERING =====
    if Input.is_action_just_pressed("jump"):
        jump_buffer_timer = jump_buffer_time
        should_jump_buffered = true
    else:
        jump_buffer_timer -= delta
        if jump_buffer_timer <= 0.0:
            should_jump_buffered = false
    
    # ===== LÓGICA DE SALTO MEJORADA =====
    var can_jump = is_on_floor() or can_coyote_jump
    
    if can_jump and should_jump_buffered:
        vertical_velocity.y = -jump_force  # Saltamos
        should_jump_buffered = false
        jump_buffer_timer = 0.0
        can_coyote_jump = false  # Consumir coyote jump
    
    # ... resto de física ...
```

#### 5.2 Tuning Recomendado

| Parámetro | Valor (ms) | Notas |
|-----------|-----------|-------|
| Coyote Time | 120 | Estándar en juegos modernos |
| Jump Buffer | 100 | Ligeramente menor que coyote |
| Doble Salto | N/A | Implementar por separado (estado de "en aire") |

#### 5.3 Doble Salto (bonus para MVP)

```gdscript
# En PlayerController.gd

export var double_jump_enabled := true
var air_jumps_used := 0

func _physics_process(delta):
    # ... coyote y buffer ...
    
    if is_on_floor():
        air_jumps_used = 0
    
    var can_double_jump = (air_jumps_used < 1) and not is_on_floor()
    var can_jump = is_on_floor() or can_coyote_jump or can_double_jump
    
    if can_jump and should_jump_buffered:
        vertical_velocity.y = -jump_force
        if not is_on_floor() and not can_coyote_jump:
            air_jumps_used += 1
        should_jump_buffered = false
        jump_buffer_timer = 0.0
```

### Referencias Documentadas

- **[web:18]** YouTube: "how to implement coyote jump & jump buffering in godot 4" (Dic 2024)  
  → Tutorial paso a paso (traducible a 3.x)
- **[web:21]** YouTube: "Fix Your Clunky Movement Controller in Godot 4.3" (Oct 2024)  
  → Explicación de importancia del buffering
- **[web:24]** Reddit: "Help with jump buffering and coyote timer"  
  → Discusión práctica de timers

---

## 6. Cámara Spring-Damper

### Objetivo

Cámara que sigue al jugador suavemente, evita clipping con geometría, se orienta según control/lookstick.

#### 6.1 Implementar `CameraController.gd`

```gdscript
# players/elias/CameraController.gd (Node3D, hijo de Elías)

extends Spatial

export var distance := 3.5
export var height := 0.8
export var spring_stiffness := 8.0  # k en "spring" physics
export var damping := 0.7  # Factor de amortiguamiento (0-1)
export var max_tilt := deg2rad(75)
export var collision_margin := 0.1

var camera: Camera3D
var spring_velocity := Vector3.ZERO

func _ready():
    camera = get_node("Camera3D")
    if camera:
        camera.current = true

func _process(delta):
    if not camera:
        return
    
    # ===== ROTACIÓN SEGÚN INPUT =====
    if Input.is_mouse_button_pressed(BUTTON_RIGHT):
        # Free-look
        var mouse_delta = get_tree().root.get_mouse_position()
        rotation.y -= mouse_delta.x * 0.005
        rotation.x -= mouse_delta.y * 0.005
        rotation.x = clamp(rotation.x, -max_tilt, max_tilt)
    else:
        # Seguir al jugador suavemente
        rotation.y = get_parent().rotation.y
    
    # ===== POSICIÓN CON SPRING-DAMPER =====
    var target_offset = Vector3(0, height, distance)
    target_offset = target_offset.rotated(Vector3.UP, rotation.y)
    
    var desired_pos = get_parent().global_transform.origin + target_offset
    var current_pos = global_transform.origin
    
    var displacement = desired_pos - current_pos
    var force = displacement * spring_stiffness - spring_velocity * damping
    spring_velocity += force * delta
    
    var new_pos = current_pos + spring_velocity * delta
    
    # ===== COLISIÓN CON GEOMETRÍA =====
    var space_state = get_world().direct_space_state
    var query = PhysicsRayQueryParameters3D.new()
    query.from = get_parent().global_transform.origin
    query.to = new_pos
    
    var result = space_state.intersect_ray(query)
    if result:
        new_pos = result.position - (result.normal * collision_margin)
    
    global_transform.origin = new_pos
    camera.look_at(get_parent().global_transform.origin + Vector3.UP * height, Vector3.UP)
```

**Configuración en Editor:**

```
Player
├── CameraRig (Node3D) [CameraController.gd]
│   ├── Camera3D
│   ├── SpringArm3D (alternativa automática)
│   └── ...
```

#### 6.2 Alternativa Simplificada (SpringArm3D built-in)

Godot 3.1+ incluye `SpringArm3D`:

```gdscript
# Usar directamente en escena:
Player
├── CameraPivot (Node3D)
├── SpringArm3D
│   └── Camera3D
```

**Ventaja:** Godot gestiona la colisión automáticamente.

### Referencias Documentadas

- **[web:35]** YouTube: "Creating a simple 3rd person camera [Godot 4]" (Feb 2024)  
  → Demostración de SpringArm3D (similar en 3.x)
- **[web:37]** Godot Docs: "Third-person camera with spring arm"  
  → Documentación oficial
- **[web:40]** YouTube: "Godot 3 : Camera Follow Player" (Feb 2018)  
  → Implementación manual de spring-damper

---

## 7. Conveyor Consistente

### Contexto

Tu `Conveyor.gd` actual es un Area3D que aplica empuje.  
Problema: Empuje no es consistente si el jugador no integra `set_external_velocity`.

### Solución: Interfaz Unificada

#### 7.1 Modificar `Conveyor.gd`

```gdscript
# scenes/common/Conveyor.gd (Area3D)

extends Area3D

export var direction := Vector3.RIGHT  # Dirección normalizada
export var speed := 3.0  # Metros por segundo
export var color_debug := Color.cyan  # Para visualización

var active_bodies := []

func _ready():
    connect("body_entered", self, "_on_body_entered")
    connect("body_exited", self, "_on_body_exited")

func _physics_process(delta):
    # ===== APLICAR EMPUJE A CUERPOS ACTIVOS =====
    for body in active_bodies:
        if body.has_method("set_external_velocity"):
            var push_velocity = direction.normalized() * speed
            body.set_external_velocity(push_velocity)

func _on_body_entered(body):
    if not active_bodies.has(body):
        active_bodies.append(body)

func _on_body_exited(body):
    active_bodies.erase(body)

# Debug visualization (opcional)
func _draw():
    if Engine.editor_hint:
        var points = PoolVector3Array([
            Vector3.ZERO,
            direction * speed * 0.5
        ])
        # draw_line_3d(points[0], points[1], color_debug)
```

#### 7.2 Estructura de Escena

```
Conveyor (Area3D) [Conveyor.gd]
├── CollisionShape3D (rectángulo plano sobre suelo)
├── MeshInstance (visual stripe animada, opcional)
```

#### 7.3 Animación de Stripes (visual feedback)

```gdscript
# Opcional: en _process(delta)
var stripe_offset := 0.0

func _process(delta):
    stripe_offset += speed * delta
    if stripe_offset > 2.0:
        stripe_offset -= 2.0
    
    # Aplicar a material UV offset
    var mat = $MeshInstance.get_active_material(0) as Material
    if mat:
        mat.uv1_offset = Vector3(stripe_offset, 0, 0)
```

### Referencias Documentadas

- **[web:60]** YouTube: "2D Platformer Conveyor Belt | Godot 4.5" (Oct 2024)  
  → Patrón de `conveyor_velocity` variable en jugador
- **[web:66]** Reddit: "Conveyor belt system"  
  → Discusión de optimización con Areas

---

## 8. FSM Simple para Enemigos DDC

### Arquitectura

DDC (Dron de Diagnóstico Corrupto) tiene 3 estados:

1. **Patrol**: Recorre ruta Path3D
2. **Alert**: Vio al jugador, cambia a rojo, dispara alarma
3. **Search**: Intenta encontrar al jugador; resetea a Patrol si falla

#### 8.1 Crear `Enemy_DDC.gd`

```gdscript
# enemies/ddc/Enemy_DDC.gd (Spatial)

extends Spatial

# ===== REFERENCIAS =====
export var patrol_path: NodePath
export var vision_range := 8.0
export var vision_angle := 60.0  # grados
export var speed := 2.0
export var search_time := 5.0

# ===== SEÑALES =====
signal state_changed(new_state)
signal player_spotted(player)

# ===== ESTADO =====
var state := "Patrol"
var path_follow: PathFollow3D
var player: Node = null
var sight_timer := 0.0

# ===== COMPONENTES =====
var mesh: MeshInstance3D
var material: SpatialMaterial
var alarm_area: Area3D

func _ready():
    # Configurar FSM
    mesh = $MeshInstance3D
    material = mesh.get_active_material(0).duplicate()
    mesh.set_surface_material(0, material)
    
    # Configurar patrulla
    var path = get_node(patrol_path)
    if path and path.get_child_count() > 0:
        path_follow = path.get_child(0)
    
    # Obtener referencia del jugador
    player = get_tree().root.find_child("PlayerElias", true, false)
    
    # Detectar alarma (Area alrededor del DDC)
    alarm_area = Area3D.new()
    alarm_area.name = "AlarmArea"
    add_child(alarm_area)
    var cs = CollisionShape3D.new()
    cs.shape = SphereShape3D.new()
    cs.shape.radius = 0.5  # Pequeña zona de activación
    alarm_area.add_child(cs)

func _physics_process(delta):
    match state:
        "Patrol":
            _patrol(delta)
        "Alert":
            _alert(delta)
        "Search":
            _search(delta)

func _patrol(delta):
    """Recorrer ruta Path3D."""
    if not path_follow:
        return
    
    path_follow.unit_offset += (speed / 10.0) * delta  # Ajustar velocidad
    if path_follow.unit_offset >= 1.0:
        path_follow.unit_offset = 0.0
    
    global_transform.origin = path_follow.global_transform.origin
    
    # ===== DETECCIÓN DE VISIÓN =====
    if _can_see_player():
        _change_state("Alert")
    
    # Reset de material
    material.albedo_color = Color.blue

func _alert(delta):
    """Vio al jugador, alertar y buscar."""
    material.albedo_color = Color.red
    
    # Disparar evento para UI/audio
    emit_signal("player_spotted", player)
    
    # Después de breve tiempo, cambiar a Search
    sight_timer += delta
    if sight_timer > 1.0:
        _change_state("Search")
        sight_timer = 0.0

func _search(delta):
    """Buscar al jugador."""
    sight_timer += delta
    
    # Girar lentamente buscando
    rotation.y += delta
    
    # Si ve al jugador de nuevo, volver a Alert
    if _can_see_player():
        _change_state("Alert")
    
    # Si no encuentra, volver a Patrol
    if sight_timer > search_time:
        _change_state("Patrol")
        sight_timer = 0.0
    
    material.albedo_color = Color.yellow

func _can_see_player() -> bool:
    """Detección de visión con cono."""
    if not player:
        return false
    
    var to_player = (player.global_transform.origin - global_transform.origin)
    var distance = to_player.length()
    
    if distance > vision_range:
        return false
    
    # Dot product para cono de visión
    var forward = -global_transform.basis.z
    var angle = acos(to_player.normalized().dot(forward))
    var max_angle = deg2rad(vision_angle / 2.0)
    
    if angle > max_angle:
        return false
    
    # Raycast para ver si hay obstrucción
    var space_state = get_world().direct_space_state
    var query = PhysicsRayQueryParameters3D.new()
    query.from = global_transform.origin
    query.to = player.global_transform.origin
    query.exclude = [self]
    
    var result = space_state.intersect_ray(query)
    if result and result.collider == player:
        return true
    
    return false

func _change_state(new_state: String):
    """Transición de estado."""
    state = new_state
    emit_signal("state_changed", new_state)
```

#### 8.2 Conectar Señales en Nivel

```gdscript
# En criogenia.gd o gestión de nivel:

func _ready():
    var ddc = $Enemy_DDC
    ddc.connect("player_spotted", self, "_on_ddc_spotted_player")

func _on_ddc_spotted_player(player):
    print("¡Alerta DDC!")
    # Activar HUD de alerta
    # Cambiar música
    # Cerrar puertas cercanas
```

### Referencias Documentadas

- **[web:61]** gdscript.com: "Godot State Machine"  
  → Arquitectura formal de FSM
- **[web:64]** gdscript Stacked FSM  
  → Versión avanzada (para futuro)
- **[web:67]** Reddit: "Bare-bones FSM"  
  → Implementación minimalista

---

## 9. Visión Cónica y Detección de Sigilo

### Amplificación del Sistema DDC: Cono de Visión Visual

#### 9.1 Implementar Cono de Visión Debuggeable

```gdscript
# enemies/ddc/VisionConeDebug.gd (Node3D, hijo de DDC)

extends Node3D

# ===== PARÁMETROS DE VISIÓN =====
export var vision_range := 8.0
export var vision_angle := 60.0  # grados
export var raycast_count := 8  # Rayos para aproximar cono
export var material_color := Color.cyan

var mesh_instance: MeshInstance3D
var vision_points := PoolVector3Array()

func _ready():
    mesh_instance = MeshInstance3D.new()
    add_child(mesh_instance)
    
    # Crear material semi-transparente
    var mat = StandardMaterial3D.new()
    mat.albedo_color = material_color
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mesh_instance.set_surface_material(0, mat)

func _process(delta):
    # ===== RECALCULAR CONO CADA FRAME =====
    _update_cone_mesh()

func _update_cone_mesh():
    """Dibujar cono de visión como malla."""
    vision_points.clear()
    
    var apex = global_transform.origin
    var forward = -global_transform.basis.z
    var right = global_transform.basis.x
    var up = global_transform.basis.y
    
    var max_angle_rad = deg2rad(vision_angle / 2.0)
    
    # Generar puntos alrededor del cono
    for i in range(raycast_count):
        var t = float(i) / raycast_count
        var angle = TAU * t
        
        var dir_on_cone = forward.rotated(up, max_angle_rad)
        dir_on_cone = dir_on_cone.rotated(forward, angle)
        
        var edge_point = apex + dir_on_cone * vision_range
        vision_points.append(edge_point)
    
    # Crear malla (simplificada: solo líneas)
    var mesh = Mesh.new()
    # ... implementar generación de mesh o usar ImmediateMesh ...
```

#### 9.2 Test Visual

```gdscript
# Añadir a _process del DDC:

func _draw_debug_vision():
    if Engine.editor_hint or OS.is_debug_build():
        # Dibujar rayo central de visión
        debug_draw_line_3d(
            global_transform.origin,
            global_transform.origin - global_transform.basis.z * vision_range,
            Color.cyan
        )
```

### Referencias Documentadas

- **[web:62]** Reddit: "How would I make a simple vision cone for enemy AI?"  
  → Explicación de dot product + raycast
- **[web:65]** playgama.com: "How can I implement a vision cone"  
  → Técnica Layer/Mask de Godot
- **[web:68]** GitHub: godot-vision-cone (plugin para Godot 4, inspirativo)  
  → Implementación profesional de raycast distribuidos

---

## 10. Diálogos y Narrativa (JSON + AudioStreamPlayer3D)

### Objetivo MVP

Implementar sistema de diálogos mínimo para:

1. Diálogos iniciales de IA/PP al despertar (Criogenia)
2. Advertencias de IA antes de alarma
3. Último monólogo antes del clímax (Acto I → Acto II)

#### 10.1 Estructura de Diálogos en JSON

```json
# res://data/dialogues/act1_criogenia.json
{
  "awakening": {
    "id": "awakening",
    "speaker": "IA_Odisea",
    "text": "Oficial Elías. Bienvenido de vuelta. Los sistemas se están recuperando.",
    "audio": "res://audio/voice/ai_awakening.ogg",
    "duration": 4.5,
    "visual_effect": "lights_flicker"
  },
  "warning_1": {
    "id": "warning_1",
    "speaker": "IA_Odisea",
    "text": "Recomiendo permanecer en criogenia. El status de la misión es...",
    "audio": "res://audio/voice/ai_warning_1.ogg",
    "duration": 3.2,
    "visual_effect": null
  },
  "pp_voice_fragment": {
    "id": "pp_voice_fragment",
    "speaker": "Programadora_Principal",
    "text": "Si la humanidad despierta... será su fin.",
    "audio": "res://audio/voice/pp_voice.ogg",
    "duration": 2.8,
    "visual_effect": "hologram_flicker"
  }
}
```

#### 10.2 Implementar `DialogueManager.gd` (AutoLoad)

```gdscript
# autoload/DialogueManager.gd

extends Node

class_name DialogueManager

# ===== SEÑALES =====
signal dialogue_started(id)
signal dialogue_ended(id)
signal line_displayed(speaker, text)

# ===== ESTADO =====
var current_dialogue: Dictionary = {}
var dialogues_bank: Dictionary = {}
var is_playing := false

func _ready():
    # Cargar todos los diálogos del Acto I
    _load_dialogues("res://data/dialogues/act1_criogenia.json")
    _load_dialogues("res://data/dialogues/act1_mantenimiento.json")

func _load_dialogues(path: String):
    """Cargar archivo JSON de diálogos."""
    if not ResourceLoader.exists(path):
        push_error("DialogueManager: Archivo no encontrado: " + path)
        return
    
    var file = File.new()
    file.open(path, File.READ)
    var json = parse_json(file.get_as_text())
    file.close()
    
    for dialogue_id in json.keys():
        dialogues_bank[dialogue_id] = json[dialogue_id]

func start_dialogue(dialogue_id: String) -> bool:
    """Iniciar una línea de diálogo."""
    if not dialogue_id in dialogues_bank:
        push_error("DialogueManager: Diálogo no encontrado: " + dialogue_id)
        return false
    
    current_dialogue = dialogues_bank[dialogue_id]
    is_playing = true
    
    emit_signal("dialogue_started", dialogue_id)
    emit_signal("line_displayed", current_dialogue.get("speaker"), current_dialogue.get("text"))
    
    # Reproducir audio si existe
    if current_dialogue.has("audio"):
        _play_audio(current_dialogue["audio"])
    
    # Aplicar efecto visual si existe
    if current_dialogue.has("visual_effect"):
        _apply_visual_effect(current_dialogue["visual_effect"])
    
    # Programar fin del diálogo
    var duration = current_dialogue.get("duration", 3.0)
    yield(get_tree(), "idle_frame")
    yield(get_tree().create_timer(duration), "timeout")
    
    end_dialogue()
    
    return true

func end_dialogue():
    """Terminar diálogo."""
    is_playing = false
    emit_signal("dialogue_ended", current_dialogue.get("id", ""))
    current_dialogue = {}

func _play_audio(audio_path: String):
    """Reproducir audio de diálogo (voz IA/PP)."""
    var audio_player = AudioStreamPlayer.new()
    audio_player.name = "DialogueAudio"
    audio_player.bus = "Voice"  # Crear bus de audio para voces
    add_child(audio_player)
    
    var stream = load(audio_path)
    if stream:
        audio_player.stream = stream
        audio_player.play()
    
    # Limpiar después de reproducir
    yield(audio_player, "finished")
    audio_player.queue_free()

func _apply_visual_effect(effect: String):
    """Aplicar efecto visual durante diálogo."""
    match effect:
        "lights_flicker":
            _flicker_environment_lights()
        "hologram_flicker":
            _hologram_appearance()
        _:
            pass

func _flicker_environment_lights():
    """Parpadeo de luces (efecto del sistema despertando)."""
    var env = get_tree().root.find_child("Environment", true, false)
    if env:
        # Reducir ambient light temporalmente
        var original_energy = env.ambient_light_energy
        env.ambient_light_energy = 0.3
        yield(get_tree().create_timer(0.2), "timeout")
        env.ambient_light_energy = original_energy

func _hologram_appearance():
    """Aparición de holograma de PP."""
    var pp_hologram = get_tree().root.find_child("PP_Hologram", true, false)
    if pp_hologram:
        pp_hologram.modulate.a = 1.0  # Fade in
        yield(get_tree().create_timer(0.5), "timeout")
```

#### 10.3 Integración con UI

```gdscript
# ui/DialogueBox.gd (CanvasLayer -> Panel)

extends Panel

var dialogue_manager: DialogueManager
var speaker_label: Label
var text_label: Label
var tween: Tween

func _ready():
    dialogue_manager = DialogueManager
    dialogue_manager.connect("dialogue_started", self, "_on_dialogue_started")
    dialogue_manager.connect("dialogue_ended", self, "_on_dialogue_ended")
    dialogue_manager.connect("line_displayed", self, "_on_line_displayed")
    
    speaker_label = $VBoxContainer/Speaker
    text_label = $VBoxContainer/Text
    modulate.a = 0.0  # Invisible al inicio

func _on_dialogue_started(id: String):
    """Mostrar caja de diálogo."""
    modulate.a = 1.0
    $AnimationPlayer.play("show")  # O tween suave

func _on_dialogue_ended(id: String):
    """Ocultar caja de diálogo."""
    $AnimationPlayer.play("hide")

func _on_line_displayed(speaker: String, text: String):
    """Mostrar texto con efecto typewriter (opcional)."""
    speaker_label.text = speaker
    
    # Efecto typewriter simple
    text_label.text = ""
    for char in text:
        text_label.text += char
        yield(get_tree().create_timer(0.02), "timeout")
```

#### 10.4 Disparo de Diálogos desde Nivel

```gdscript
# En criogenia.gd:

func _ready():
    # Despertar de Elías
    yield(DialogueManager.start_dialogue("awakening"), "completed")
    yield(get_tree().create_timer(2.0), "timeout")
    
    # Advertencia
    yield(DialogueManager.start_dialogue("warning_1"), "completed")
    
    # ... continuar gameplay ...
```

### Referencias Documentadas

- **[web:88]** YouTube: "Writing and Loading Conversations in Godot: Dialogue Tutorial 1"  
  → Carga JSON básica
- **[web:91]** GitHub: GodotDialogueResourceSystem  
  → Alternativa con .tres files
- **[web:94]** itch.io: "Branching Dialogue Graph Godot"  
  → Sistema JSON completo con ramificaciones
- **[web:97]** YouTube: "How to make a JSON Dialogue System in Godot"  
  → Tutorial comprehensivo

### Audio 3D Posicional (AudioStreamPlayer3D)

Para que la voz de IA suene "desde" la consola:

```gdscript
# En DialogueManager o UI:

func _play_audio_3d(audio_path: String, position_3d: Vector3):
    """Reproducir audio desde posición en el mundo."""
    var audio_player = AudioStreamPlayer3D.new()
    audio_player.name = "DialogueAudio3D"
    audio_player.bus = "Voice"
    audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
    audio_player.unit_db = 0.0
    audio_player.max_db = 3.0
    audio_player.global_position = position_3d
    get_tree().root.add_child(audio_player)
    
    var stream = load(audio_path)
    if stream:
        audio_player.stream = stream
        audio_player.play()
    
    yield(audio_player, "finished")
    audio_player.queue_free()
```

### Referencias para Audio 3D

- **[web:92]** Godot Docs: AudioStreamPlayer3D  
  → Documentación oficial
- **[web:95]** Godot Docs: Audio Streams (3.0)  
  → Guía de audio posicional

---

## 11. Artefactos y Herramientas de Desarrollo

### 11.1 EditorScripts y Plugins Ligeros

#### Herramienta: Debug Overlay Global

```gdscript
# addons/debug_overlay/DebugOverlay.gd

extends CanvasLayer

var is_visible := false
var display_text := ""

func _ready():
    layer = 255  # Renderizar encima de todo

func _process(delta):
    if Input.is_action_just_pressed("debug_toggle"):  # Ctrl+D
        is_visible = not is_visible
    
    if is_visible:
        display_text = _gather_debug_info()
        update()

func _draw():
    if not is_visible:
        return
    
    draw_rect(Rect2(10, 10, 300, 400), Color.black.with_a(0.8))
    draw_string(
        load("res://fonts/default_font.tres"),
        Vector2(20, 30),
        display_text,
        Color.green
    )

func _gather_debug_info() -> String:
    var player = get_tree().root.find_child("PlayerElias", true, false)
    if not player:
        return "No player found"
    
    var info = """
    === PLAYER DEBUG ===
    Position: %.2f, %.2f, %.2f
    Velocity: %.2f (h), %.2f (v)
    Platform Vel: %.2f
    On Floor: %s
    Can Jump: %s
    
    === ENVIRONMENT ===
    Time: %.2f
    FPS: %d
    """ % [
        player.global_transform.origin.x,
        player.global_transform.origin.y,
        player.global_transform.origin.z,
        player.horizontal_velocity.length(),
        player.vertical_velocity.y,
        player.platform_velocity.length(),
        player.is_on_floor(),
        # can_jump (si existe),
        OS.get_ticks_msec() / 1000.0,
        Engine.get_frames_per_second()
    ]
    
    return info
```

#### Herramienta: Editor de Volúmenes de Gravedad

```gdscript
# addons/gravity_volume_editor/GravityVolumePlugin.gd

extends EditorPlugin

class_name GravityVolumePlugin

func _handles(object):
    return object is GravityVolume

func _edit(object):
    pass

func _make_visible(visible):
    pass

# ... Gizmo de visualización de vectores de gravedad ...
```

### 11.2 Escenas de Sandbox

#### Laboratorio de Movimiento

```
res://scenes/labs/
├── lab_movement.tscn
│   ├── Player (PlayerController instancia)
│   ├── TestPlatforms (varias alturas)
│   ├── DebugUI (Panel con sliders para tunear)
│   └── CameraController
```

**Debug UI GDScript:**

```gdscript
# En DebugUI:

export var player_path: NodePath
var player: Node

func _ready():
    player = get_node(player_path)
    $VBoxContainer/MaxSpeedSlider.connect("value_changed", self, "_on_max_speed_changed")

func _on_max_speed_changed(value: float):
    player.max_speed = value
    $VBoxContainer/MaxSpeedLabel.text = "Max Speed: %.2f" % value
```

### 11.3 Recursos Documentados

#### Tuning Reference Sheet

```gdscript
# data/TuningReference.gd (autoload, solo para documentación)

class_name TuningReference

# Valores recomendados para "feel" Mario-like en Criogenia

const PLAYER_CONFIG = {
    "max_speed": 5.5,
    "acceleration": 20.0,
    "gravity": 25.0,
    "jump_force": 12.0,
    "double_jump_enabled": true,
    "coyote_time": 0.12,
    "jump_buffer_time": 0.1,
    "snap_len": 0.5,
}

const PLATFORM_CONFIG = {
    "platform_speed": 2.5,
    "platform_wait_time": 1.0,
    "snap_adhesion": true,
}

const CAMERA_CONFIG = {
    "distance": 3.5,
    "height": 0.8,
    "spring_stiffness": 8.0,
    "damping": 0.7,
}
```

---

## 12. Cronograma de Implementación Sugerido

### Fase 1: Núcleo de Movimiento (Semana 1-2)

| Día | Tarea | Prioridad | Horas Est. |
|-----|-------|-----------|-----------|
| L1-V1 | Implementar `set_external_velocity()` + `move_and_slide_with_snap()` | CRÍTICA | 6 |
| L1-V1 | Integrar MovingPlatform con transferencia de velocidad | CRÍTICA | 4 |
| L2-V2 | Añadir Coyote Time + Input Buffering | CRÍTICA | 3 |
| L2-V2 | Doble salto (bonus) | ALTA | 2 |
| L3-V3 | Pruebas A/B de "feel" | ALTA | 4 |

**Entregable:** MVP de jugabilidad base. Elías se mueve suavemente sobre plataformas.

### Fase 2: Sistemas Secundarios (Semana 3-4)

| Día | Tarea | Prioridad | Horas Est. |
|-----|-------|-----------|-----------|
| L1-V1 | Implementar `CameraController.gd` (spring-damper) | ALTA | 5 |
| L1-V2 | Perfiles de aceleración con Curve1D | MEDIA | 3 |
| L2-V2 | Conveyor básico + test | ALTA | 3 |
| L2-V3 | FSM simple DDC (Patrol → Alert → Search) | MEDIA | 5 |
| L3-V3 | Visión cónica debug (gizmo) | MEDIA | 4 |

**Entregable:** Cámara fluida, plataformas dinámicas, enemigo simple.

### Fase 3: Narrativa & Pulido (Semana 5)

| Día | Tarea | Prioridad | Horas Est. |
|-----|-------|-----------|-----------|
| L1-V1 | Sistema de diálogos JSON + DialogueManager | CRÍTICA | 6 |
| L1-V2 | UI de diálogo + Typewriter effect | ALTA | 4 |
| L2-V2 | Audio 3D (voces IA/PP) + AudioStreamPlayer3D | ALTA | 3 |
| L2-V3 | Efectos visuales de diálogos (flickering, holograma) | MEDIA | 4 |
| L3-V3 | Escenas de Criogenia graybox + layout Acto I | CRÍTICA | 8 |

**Entregable:** Primera escena jugable completa (Criogenia). Narrativa integrada.

### Fase 4: Iteración & Optimización (Semana 6+)

| Tarea | Descripción |
|-------|-------------|
| Balanceo de dificultad | Ajustar velocidad de DDC, rangos de visión, alarmas |
| Optimización GLES2 | Perfil en Android; reducir luces si es necesario |
| Audio/SFX | Añadir ambientes, pasos, alertas DDC |
| Pulido visual | Materiales low-poly, neón/niebla, VFX |
| Playtest | Feedback de feel, control responsivo, frustración |

---

## Resumen de Referencias Documentadas

### Por Sistema

| Sistema | Referencias Clave |
|---------|-------------------|
| **Plataforma + Velocidad** | web:16, web:17, web:25, web:20 |
| **PathFollow Curvas** | web:33, web:41, web:23 |
| **Aceleración Curves** | web:36, web:39, web:34 |
| **Coyote Time** | web:18, web:21, web:24 |
| **Cámara Spring** | web:35, web:37, web:40 |
| **Conveyor** | web:60, web:66 |
| **FSM Enemigos** | web:61, web:64, web:67 |
| **Visión Cónica** | web:62, web:65, web:68 |
| **Diálogos JSON** | web:88, web:91, web:94, web:97 |
| **Audio 3D** | web:92, web:95 |

---

## Próximos Pasos Inmediatos

1. **Hoy:** Iniciar Fase 1, Día 1
   - [ ] Crear rama git: `feature/platform-velocity`
   - [ ] Duplicar `PlayerController.gd` → crear versión mejorada
   - [ ] Implementar `set_external_velocity()` y snap

2. **Esta semana:**
   - [ ] Integrar en MovingPlatform
   - [ ] Escena de prueba sandbox
   - [ ] Coyote time + input buffering

3. **Próxima semana:**
   - [ ] Cámara spring-damper
   - [ ] Conveyor
   - [ ] Primer DDC funcional

---

**Documento compilado:** 01/12/2025  
**Para:** Odisea: El Arca Silenciosa MVP  
**By:** Research & Architecture Agent