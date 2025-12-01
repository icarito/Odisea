# Odisea MVP: Índice de APIs y Referencias Rápidas
## Godot 3.x | Cheat Sheet para Desarrollo

---

## 1. APIs Propuestas para Godot 3.x (KinematicBody 3D)

### 1.1 PlayerController.gd - Interfaz Pública

```gdscript
extends KinematicBody3D

# ===== VELOCIDAD EXTERNA (nueva interfaz) =====
func set_external_velocity(v: Vector3) -> void:
    # Llamada por plataformas/conveyor
    # Acumula platform_velocity; se desvanece por frame
    platform_velocity = v

# ===== ESTADO DE SALTO =====
func get_can_jump() -> bool:
    # Retorna true si puede saltar (suelo O coyote_time)
    return is_on_floor() or can_coyote_jump

# ===== DEBUG =====
func get_debug_info() -> Dictionary:
    return {
        "position": global_transform.origin,
        "velocity": horizontal_velocity.length(),
        "vertical": vertical_velocity.y,
        "on_floor": is_on_floor(),
        "can_jump": get_can_jump(),
        "platform_velocity": platform_velocity.length(),
        "state": current_state,
    }
```

### 1.2 MovingPlatform.gd - Interfaz Pública

```gdscript
extends Spatial

# ===== CONFIGURACIÓN =====
export var point_a := Vector3.ZERO
export var point_b := Vector3.ZERO
export var speed := 2.0
export var wait_time := 1.0

# ===== SEÑALES =====
signal on_reached_point(point: Vector3)

# ===== CONTROL =====
func set_speed(new_speed: float) -> void:
    speed = new_speed

func get_current_velocity() -> Vector3:
    # Retorna velocidad instantánea de la plataforma
    return (global_transform.origin - last_position) / (1.0 / 60.0)
```

### 1.3 Conveyor.gd - Interfaz Pública

```gdscript
extends Area3D

export var direction := Vector3.RIGHT
export var speed := 3.0

# ===== CONTROL =====
func set_push_vector(dir: Vector3, spd: float) -> void:
    direction = dir.normalized()
    speed = spd

func get_active_bodies() -> Array:
    return active_bodies
```

### 1.4 Enemy_DDC.gd - Interfaz Pública

```gdscript
extends Spatial

# ===== SEÑALES =====
signal state_changed(new_state: String)
signal player_detected(player: Node)
signal alarm_triggered

# ===== ESTADO =====
func get_current_state() -> String:
    return state

func set_search_duration(seconds: float) -> void:
    search_time = seconds
```

### 1.5 DialogueManager.gd - Interfaz Pública (AutoLoad)

```gdscript
extends Node

class_name DialogueManager

# ===== SEÑALES =====
signal dialogue_started(id: String)
signal dialogue_ended(id: String)
signal line_displayed(speaker: String, text: String)

# ===== OPERACIONES =====
func start_dialogue(id: String) -> bool:
    # Inicia diálogo; retorna true si existe
    # Yield: dialogue_ended(id)

func is_dialogue_playing() -> bool:
    return is_playing

func load_dialogues_from_file(path: String) -> bool:
    # Carga archivo JSON; retorna true si éxito

func get_dialogue_duration(id: String) -> float:
    # Retorna duración del diálogo en segundos
```

---

## 2. Patrones Comunes en Godot 3.x

### 2.1 KinematicBody + move_and_slide_with_snap

```gdscript
func _physics_process(delta):
    # Aplicar gravedad
    velocity.y -= gravity * delta
    
    # Snap cuando en suelo
    var snap = Vector3.DOWN * 0.5 if is_on_floor() else Vector3.ZERO
    
    # Mover
    velocity = move_and_slide_with_snap(velocity, snap, Vector3.UP, true)
```

### 2.2 Detección de Raycast para Bordes

```gdscript
var edge_raycast: RayCast  # Configurable en editor

func check_edge() -> bool:
    # Detecta si hay borde adelante
    return not edge_raycast.is_colliding()
```

### 2.3 Interpolación Suave (lerp)

```gdscript
var target_velocity := Vector3.ZERO
var acceleration := 10.0

func _physics_process(delta):
    # Suave interpolación hacia target
    velocity = velocity.linear_interpolate(target_velocity, acceleration * delta)
```

### 2.4 FSM Básica con Match

```gdscript
enum STATE { IDLE, WALK, JUMP }
var current_state = STATE.IDLE

func _physics_process(delta):
    match current_state:
        STATE.IDLE:
            _handle_idle()
        STATE.WALK:
            _handle_walk(delta)
        STATE.JUMP:
            _handle_jump(delta)
```

### 2.5 Señales y Conexión

```gdscript
# En _ready:
connect("timeout", self, "_on_timeout")

# Desconectar
disconnect("timeout", self, "_on_timeout")

# Emitir señal personalizada
emit_signal("custom_event", param1, param2)
```

---

## 3. Configuración Crítica en Editor

### 3.1 KinematicBody3D Inspector

```
KinematicBody3D (PlayerController)
├── Transform: global_position
├── Physics
│   ├── Collision → Layers: Player layer
│   ├── Collision → Mask: Environment + Platforms + Items
│   └── Sync to Physics: ON (si se anima con AnimationPlayer)
├── Script: PlayerController.gd
└── Variables exportadas (vistas en Inspector)
```

### 3.2 Area3D (para detección)

```
Area3D (MovingPlatform/Area)
├── Collision → Shape: (configurado)
├── Collision → Layers: Platforms
├── Collision → Mask: Player
└── Conectar señales:
    - body_entered
    - body_exited
```

### 3.3 AudioStreamPlayer3D

```
AudioStreamPlayer3D
├── Stream: (cargar .ogg o .wav)
├── Volume DB: 0
├── Bus: Voice (crear si no existe)
├── Attenuation Model: Inverse Distance
├── Unit DB: 0
├── Max DB: 3
└── Distance Attenuation: ON
```

---

## 4. Estructura de Carpetas Recomendada

```
res://
├── players/
│   └── elias/
│       ├── PlayerController.gd       [CRÍTICO]
│       ├── CameraController.gd
│       ├── player_elias.tscn
│       └── animations/
│           ├── idle.anim
│           ├── walk.anim
│           └── jump.anim
├── enemies/
│   └── ddc/
│       ├── Enemy_DDC.gd             [CRÍTICO]
│       ├── enemy_ddc.tscn
│       └── materials/
├── scenes/
│   ├── common/
│   │   ├── MovingPlatform.gd        [CRÍTICO]
│   │   ├── MovingPlatform.tscn
│   │   ├── Conveyor.gd              [CRÍTICO]
│   │   ├── Conveyor.tscn
│   │   ├── Environment.tscn
│   │   └── SpawnPoint.tscn
│   ├── levels/
│   │   ├── act1/
│   │   │   ├── criogenia.tscn       [CRÍTICO - MVP]
│   │   │   ├── criogenia.gd
│   │   │   └── assets/
│   │   └── labs/
│   │       └── lab_movement.tscn    [HERRAMIENTA]
│   └── ui/
│       ├── DialogueBox.gd
│       └── DebugOverlay.gd
├── data/
│   ├── Curves/
│   │   ├── accel_snappy.tres
│   │   └── accel_smooth.tres
│   ├── dialogues/
│   │   ├── act1_criogenia.json      [CRÍTICO]
│   │   └── act1_mantenimiento.json
│   └── TuningReference.gd
├── autoload/
│   ├── DialogueManager.gd           [CRÍTICO]
│   ├── PlayerManager.gd
│   └── GameState.gd
├── audio/
│   └── voice/
│       ├── ai_awakening.ogg
│       ├── ai_warning_1.ogg
│       └── pp_voice.ogg
├── addons/
│   ├── debug_overlay/
│   ├── gravity_volume_editor/
│   └── simplified_flightsim/
└── project.godot
```

---

## 5. Checklist de Configuración Inicial

### 5.1 Project.godot

```ini
[rendering]
quality/driver/driver_name="GLES2"
quality/shadows/shadow_atlas_size=2048

[input]
forward={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":87,"unicode":0,"echo":false,"script":null) ]
}
jump={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":32,"unicode":0,"echo":false,"script":null) ]
}
```

### 5.2 Audio Bus Setup

```
Master (AutoLoad)
├── Voice (para IA/PP)
│   └── Effects: Reverb pequeño
├── SFX (efectos de juego)
│   └── Effects: Compressor
└── Ambient (ruido de fondo)
    └── Effects: Reverb grande
```

### 5.3 Capas de Colisión

```
Layer 1: Player
Layer 2: Environment
Layer 3: Platforms
Layer 4: Enemies
Layer 5: Items
Layer 6: Interactables
Layer 7: (libre)
Layer 8: (libre)
...
```

---

## 6. Comandos y Atajos Útiles

### 6.1 EditorScript para Setup Rápido

```gdscript
# tool/setup_odisea_project.gd (ejecutar con F5)

extends EditorScript

func _run():
    # Crear carpetas necesarias
    var paths = [
        "res://players/elias",
        "res://enemies/ddc",
        "res://data/curves",
        "res://data/dialogues",
        "res://audio/voice",
    ]
    
    for path in paths:
        DirAccess.make_absolute(path)
    
    print("Odisea project structure created!")
```

### 6.2 Atajos Recomendados (editor_layouts.cfg)

```
[Window Layouts]
Default=2
Debug Overlay=3
Play=4
```

---

## 7. Debugging y Profiling

### 7.1 Consola Debug

```gdscript
# Imprimir información de debug
print("Player velocity: %.2f" % velocity.length())
print_debug("Estado: %s" % state)
push_error("Error crítico!")
push_warning("Advertencia")
```

### 7.2 Monitor Integrado (Ctrl+Shift+M)

```
- FPS
- Object count
- Physics objects
- Memory
```

### 7.3 Profiler Integrado (Debugger → Profiler)

```
- Frame time
- Physics step time
- Script time
```

---

## 8. Comandos GDScript Esenciales

### 8.1 Yield y Corrutinas

```gdscript
# Esperar evento
yield(object, "signal_name")

# Esperar frames
yield(get_tree(), "idle_frame")

# Esperar tiempo
yield(get_tree().create_timer(2.0), "timeout")

# Esperar animación
yield(animation_player, "animation_finished")
```

### 8.2 Búsqueda de Nodos

```gdscript
# Buscar por nombre
var player = get_tree().root.find_child("PlayerElias", true, false)

# Buscar por grupo
var enemies = get_tree().get_nodes_in_group("enemies")

# Obtener nodo en árbol
var sibling = get_sibling()
var parent = get_parent()
var child = get_child(0)
```

### 8.3 Transformaciones

```gdscript
# Posición global
global_transform.origin = Vector3(0, 1, 0)

# Rotación relativa
rotation.y += 0.1

# Escala
scale = Vector3(2, 2, 2)

# Mirar hacia
look_at(target_position, Vector3.UP)
```

---

## 9. Referencias a Documentación Oficial

### Godot 3.6 Docs

| Tema | URL |
|------|-----|
| KinematicBody | https://docs.godotengine.org/en/3.6/classes/class_kinematicbody.html |
| move_and_slide | https://docs.godotengine.org/en/3.6/tutorials/physics/using_kinematic_body.html |
| AnimationTree | https://docs.godotengine.org/en/3.6/tutorials/animation/animation_trees.html |
| Curves | https://docs.godotengine.org/en/3.6/tutorials/io/data_formats/json.html |
| AudioStreamPlayer3D | https://docs.godotengine.org/en/3.6/classes/class_audiostreamplayer3d.html |
| Area3D | https://docs.godotengine.org/en/3.6/classes/class_area.html |

---

## 10. Troubleshooting Rápido

| Problema | Causa Común | Solución |
|----------|------------|----------|
| Jugador se desliza de plataforma | Sin snap | Usar `move_and_slide_with_snap()` |
| Salto no funciona bien | Coyote time ausente | Implementar timer de coyote |
| Entrada lag | Input buffering ausente | Añadir input buffer timer |
| Cámara clipping | Sin colisión de cámara | Usar SpringArm3D |
| Diálogos no se reproducen | Path JSON incorrecto | Verificar `res://data/dialogues/` |
| Audio silencioso | Volumen a -80dB | Revisar VolumeDB en AudioStreamPlayer |
| DDC no detecta jugador | Máscara de colisión incorrecta | Configurar Layers/Mask |
| Animaciones entrecortadas | Interpolación linear | Cambiar a nearest si necesario |

---

## 11. Performance Tips (GLES2)

### 11.1 Optimizaciones Críticas

```gdscript
# Evitar queries costosas en _process
# ❌ Mal:
func _process(delta):
    var space_state = get_world().direct_space_state
    for i in 100:
        space_state.intersect_ray(...)

# ✅ Bien:
var space_state: PhysicsDirectSpaceState
func _ready():
    space_state = get_world().direct_space_state

func _process(delta):
    # Usar space_state cacheado
```

### 11.2 Reducir Luces Dinámicas

```gdscript
# En Environment.tscn:
# - Max lights per object: 2 (en lugar de 4)
# - Use baked lighting cuando sea posible
# - Limit shadow map sizes: 1024x1024
```

### 11.3 LOD Simple

```gdscript
func _process(delta):
    var dist_to_camera = global_transform.origin.distance_to(get_viewport().get_camera_3d().global_transform.origin)
    
    if dist_to_camera > 20:
        # Reducir detalle, apagar efectos
        $DetailMesh.visible = false
    else:
        $DetailMesh.visible = true
```

---

**Documento de Referencia | Odisea MVP | 01/12/2025**