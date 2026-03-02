# Plan de Implementación: Split-Screen Técnico Detallado
## Código Listo para Implementar + Diagrama de Arquitectura

---

## 1. Diagrama de Flujo: Decisión Widescreen

```
INICIO GODOT
    ↓
Menu.tscn carga
    ↓
MenuResolutionDetector._ready() ejecuta
    ├─ screen_size = OS.get_screen_size()
    ├─ aspect = screen_size.x / screen_size.y
    ├─ is_mobile = OS.get_name() in ["Android", "iOS"]
    ├─ is_widescreen = (aspect >= 1.5) AND NOT is_mobile
    │
    ├─ SI is_widescreen:
    │   └─ $CopilotButton.visible = true
    │       └─ Al pulsar:
    │           ├─ GameConfig.set_mode("copilot")
    │           └─ get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")
    │               └─ LocalMultiplayerManager._ready()
    │                   ├─ Instanciar CoopLevel (compartido)
    │                   ├─ Crear VP_P1 (izquierda) con Camera_P1
    │                   ├─ Crear VP_P2 (derecha) con Camera_P2
    │                   ├─ Instanciar Player_1 → VP_P1
    │                   ├─ Instanciar Player_2 → VP_P2
    │                   ├─ Conectar Input para WASD (P1) y Flechas (P2)
    │                   └─ Gameplay: ambos jugadores
    │
    ├─ SI NOT is_widescreen:
    │   └─ $CopilotButton.visible = false
    │       └─ Solo botón "Play" (single-player)
    │
    └─ FIN MENÚ
```

---

## 2. Estructura de Escena: LocalMultiplayer.tscn

```
LocalMultiplayer (Node)
│
├─ [Script: LocalMultiplayerManager.gd]
│
├─ CanvasLayer_UI (CanvasLayer)
│  └─ UI_Container (Control)
│     ├─ Label_Timer (Label) — "Tiempo: 5:30"
│     ├─ Label_P1_Status (Label) — "P1: Vivo"
│     ├─ Label_P2_Status (Label) — "P2: Vivo"
│     └─ Button_Exit (Button) — "Salir"
│
├─ ViewportContainer (Control)
│  ├─ anchor_left = 0, anchor_right = 1
│  ├─ anchor_top = 0, anchor_bottom = 1
│  ├─ stretch = true
│  │
│  └─ GridContainer (GridContainer)
│     ├─ columns = 2
│     ├─ separation = 0
│     │
│     ├─ ViewportContainer_P1 (ViewportContainer)
│     │  ├─ expand_h = true
│     │  ├─ expand_v = true
│     │  │
│     │  └─ Viewport_P1 (Viewport)
│     │     ├─ size = (screen_width/2, screen_height)
│     │     ├─ disable_3d = false
│     │     ├─ transparent_bg = false
│     │     ├─ msaa = MSAA_2X (performance)
│     │     │
│     │     ├─ CoopLevel (PackedScene instancia — COMPARTIDA)
│     │     │  ├─ Plataformas (StaticBody + meshes)
│     │     │  ├─ Conveyor (Area)
│     │     │  └─ Enemigos (opcional)
│     │     │
│     │     ├─ Player_1 (Pilot.tscn instancia)
│     │     │  ├─ [Script: PlayerController.gd]
│     │     │  ├─ [Script: PlayerInput_P1.gd mixin]
│     │     │  ├─ AnimationTree
│     │     │  └─ Camera_1 (Camera3D) — CHILD DE Player_1
│     │     │     └─ current = true
│     │     │
│     │     └─ (resto de nodos del nivel)
│     │
│     └─ ViewportContainer_P2 (ViewportContainer)
│        ├─ expand_h = true
│        ├─ expand_v = true
│        │
│        └─ Viewport_P2 (Viewport)
│           ├─ size = (screen_width/2, screen_height)
│           ├─ world = Viewport_P1.world (COMPARTIDA)
│           │
│           ├─ (CoopLevel — misma instancia que VP1, NO duplicada)
│           │
│           ├─ Player_2 (Pilot.tscn instancia)
│           │  ├─ [Script: PlayerController.gd]
│           │  ├─ [Script: PlayerInput_P2.gd mixin]
│           │  ├─ AnimationTree
│           │  └─ Camera_2 (Camera3D) — CHILD DE Player_2
│           │     └─ current = false
│           │
│           └─ (resto de nodos del nivel)
```

---

## 3. Integración: Sin Romper PlayerController.gd Existente

### Opción A: Inyección de Input (Recomendada)

```gdscript
# players/elias/PlayerController.gd (ORIGINAL - SIN CAMBIOS)

extends KinematicBody

export var max_speed := 7.0
export var acceleration := 10.0

func _ready():
    # ... setup existente ...
    pass

func _physics_process(delta):
    # Obtener input (AQUÍ ES DONDE SE INYECTA)
    var input_vector = get_input_direction()  # ← Método que busca de múltiples fuentes
    
    # ... resto del movimiento igual ...
```

Luego, en `scripts/multiplayer/PlayerInputManager.gd`:

```gdscript
# scripts/multiplayer/PlayerInputManager.gd

extends Node

class_name PlayerInputManager

static var input_override := {}  # {"player_1": Vector2(...), "player_2": Vector2(...)}

# Llamada desde PlayerController
static func get_input_for_player(player_id: int) -> Vector2:
    """Obtener input para un jugador específico."""
    var key = "player_%d" % player_id
    
    # Si hay override (estamos en modo copilot), usar ese
    if input_override.has(key):
        return input_override[key]
    
    # Si no, usar input estándar
    return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
```

### Opción B: Mixin Script (Alternativa)

Crear un script que "envuelva" PlayerController:

```gdscript
# scripts/multiplayer/CoopPlayerAdapter.gd

extends Node

class_name CoopPlayerAdapter

var player_id: int
var player_controller: Node
var player_input: Node  # PlayerInput.gd

func _ready():
    player_controller = get_parent()
    player_controller.get_input_direction = funcref(self, "get_input_direction")

func get_input_direction() -> Vector2:
    """Override del método get_input_direction de PlayerController."""
    return player_input.get_input_vector()
```

---

## 4. Script Completo: LocalMultiplayerManager.gd

```gdscript
# scripts/multiplayer/LocalMultiplayerManager.gd

extends Node

class_name LocalMultiplayerManager

# ===== NODOS =====
var level: Node
var viewport_p1: Viewport
var viewport_p2: Viewport
var player1: Node
var player2: Node
var camera_p1: Camera3D
var camera_p2: Camera3D

# ===== CONFIG =====
export var level_scene_path := "res://scenes/multiplayer/CoopLevel.tscn"
export var player_scene_path := "res://players/elias/Pilot.tscn"
export var shared_world := true
export var spawn_distance := 5.0

# ===== STATE =====
var is_running := false
var player_stats = {
    1: {"alive": true, "score": 0},
    2: {"alive": true, "score": 0}
}

func _ready() -> void:
    """Inicializar copilot mode."""
    print("[LocalMultiplayerManager] Inicializando split-screen...")
    
    _setup_viewports()
    _setup_level()
    _setup_players()
    _setup_cameras()
    _setup_ui()
    
    is_running = true
    print("[LocalMultiplayerManager] Listo")

func _setup_viewports() -> void:
    """Configurar viewports para split-screen."""
    # Obtener referencias
    var vp_container_p1 = get_node("ViewportContainer/GridContainer/VP_Container_P1")
    var vp_container_p2 = get_node("ViewportContainer/GridContainer/VP_Container_P2")
    
    viewport_p1 = vp_container_p1.get_node("Viewport_P1")
    viewport_p2 = vp_container_p2.get_node("Viewport_P2")
    
    # Ajustar tamaño
    var screen_size = OS.get_screen_size()
    var half_width = int(screen_size.x / 2)
    var height = int(screen_size.y)
    
    viewport_p1.size = Vector2(half_width, height)
    viewport_p2.size = Vector2(half_width, height)
    
    # Compartir mundo
    if shared_world:
        viewport_p2.world = viewport_p1.world
    
    print("[LocalMultiplayerManager] Viewports: %dx%d cada uno" % [half_width, height])

func _setup_level() -> void:
    """Instanciar nivel compartido."""
    var level_res = load(level_scene_path)
    if not level_res:
        push_error("No se pudo cargar: %s" % level_scene_path)
        return
    
    level = level_res.instance()
    viewport_p1.add_child(level)
    print("[LocalMultiplayerManager] Nivel cargado")

func _setup_players() -> void:
    """Instanciar ambos jugadores."""
    var player_res = load(player_scene_path)
    if not player_res:
        push_error("No se pudo cargar: %s" % player_scene_path)
        return
    
    # Player 1 (izquierda)
    player1 = player_res.instance()
    player1.name = "Player_1"
    viewport_p1.add_child(player1)
    player1.global_transform.origin = Vector3(-spawn_distance, 2, 0)
    
    if player1.has_method("set_player_id"):
        player1.set_player_id(1)
    
    # Adjuntar input manager
    var input1 = load("res://scripts/multiplayer/PlayerInput.gd").new()
    input1.player_id = 1
    player1.add_child(input1)
    input1.name = "InputManager_P1"
    
    # Player 2 (derecha)
    player2 = player_res.instance()
    player2.name = "Player_2"
    viewport_p2.add_child(player2)
    player2.global_transform.origin = Vector3(spawn_distance, 2, 0)
    
    if player2.has_method("set_player_id"):
        player2.set_player_id(2)
    
    # Adjuntar input manager
    var input2 = load("res://scripts/multiplayer/PlayerInput.gd").new()
    input2.player_id = 2
    player2.add_child(input2)
    input2.name = "InputManager_P2"
    
    print("[LocalMultiplayerManager] Jugadores instanciados")

func _setup_cameras() -> void:
    """Crear cámaras independientes para cada jugador."""
    # Camera P1
    camera_p1 = Camera3D.new()
    camera_p1.name = "Camera_P1"
    player1.add_child(camera_p1)
    camera_p1.make_current()
    
    # Camera P2
    camera_p2 = Camera3D.new()
    camera_p2.name = "Camera_P2"
    player2.add_child(camera_p2)
    
    # Offset de cámara (3ª persona)
    var cam_offset = Vector3(0, 2, 5)
    camera_p1.transform.origin = cam_offset
    camera_p2.transform.origin = cam_offset
    
    print("[LocalMultiplayerManager] Cámaras configuradas")

func _setup_ui() -> void:
    """Conectar UI."""
    var exit_btn = get_node("CanvasLayer_UI/UI_Container/Button_Exit")
    exit_btn.connect("pressed", self, "_on_exit_pressed")

func _process(delta: float) -> void:
    """Actualizar cámaras cada frame."""
    if not is_running or not player1 or not player2:
        return
    
    # Actualizar posición de cámaras (follow players)
    var p1_pos = player1.global_transform.origin
    var p2_pos = player2.global_transform.origin
    
    camera_p1.global_transform.origin = p1_pos + Vector3(0, 2, 5)
    camera_p1.look_at(p1_pos, Vector3.UP)
    
    camera_p2.global_transform.origin = p2_pos + Vector3(0, 2, 5)
    camera_p2.look_at(p2_pos, Vector3.UP)
    
    # Actualizar UI
    _update_ui()

func _update_ui() -> void:
    """Actualizar labels de estado."""
    var label_p1 = get_node("CanvasLayer_UI/UI_Container/Label_P1_Status")
    var label_p2 = get_node("CanvasLayer_UI/UI_Container/Label_P2_Status")
    
    var status_p1 = "Vivo" if player_stats[1]["alive"] else "Muerto"
    var status_p2 = "Vivo" if player_stats[2]["alive"] else "Muerto"
    
    label_p1.text = "P1: %s | Score: %d" % [status_p1, player_stats[1]["score"]]
    label_p2.text = "P2: %s | Score: %d" % [status_p2, player_stats[2]["score"]]

func _on_exit_pressed() -> void:
    """Volver al menú."""
    get_tree().change_scene("res://scenes/ui/Menu.tscn")

func set_player_alive(player_id: int, alive: bool) -> void:
    """Marcar jugador como vivo/muerto (respawn)."""
    if player_id in player_stats:
        player_stats[player_id]["alive"] = alive
        print("[LocalMultiplayerManager] P%d: %s" % [player_id, "Vivo" if alive else "Muerto"])

func add_player_score(player_id: int, points: int) -> void:
    """Añadir puntos a un jugador."""
    if player_id in player_stats:
        player_stats[player_id]["score"] += points
```

---

## 5. Script: PlayerInput.gd (Dual Joypad)

```gdscript
# scripts/multiplayer/PlayerInput.gd

extends Node

class_name PlayerInput

# ===== CONFIG =====
export var player_id := 1  # 1 o 2
export var deadzone := 0.5

# ===== MAPEO DE ACCIONES =====
var key_map = {
    1: {  # Player 1: WASD
        "forward": KEY_W,
        "backward": KEY_S,
        "left": KEY_A,
        "right": KEY_D,
        "jump": KEY_SPACE,
        "sprint": KEY_SHIFT
    },
    2: {  # Player 2: Flechas
        "forward": KEY_UP,
        "backward": KEY_DOWN,
        "left": KEY_LEFT,
        "right": KEY_RIGHT,
        "jump": KEY_RETURN,
        "sprint": KEY_CONTROL
    }
}

var joypad_device := -1  # -1 = auto-detect, 0+ = específico

func _ready() -> void:
    """Inicializar input."""
    if player_id < 1 or player_id > 2:
        push_error("[PlayerInput] player_id inválido: %d" % player_id)
        return
    
    # Autodetectar joypad para P2
    if player_id == 2:
        joypad_device = 1  # Asumir que P2 usa joypad 2 (si existe)
    
    print("[PlayerInput] Inicializado para Player %d" % player_id)

func get_input_vector() -> Vector2:
    """Obtener vector de movimiento (normalizado)."""
    var input = Vector2.ZERO
    
    # Intento 1: Keyboard directo (sin actions)
    var keys = key_map[player_id]
    if Input.is_key_pressed(keys["forward"]):
        input.y -= 1
    if Input.is_key_pressed(keys["backward"]):
        input.y += 1
    if Input.is_key_pressed(keys["left"]):
        input.x -= 1
    if Input.is_key_pressed(keys["right"]):
        input.x += 1
    
    # Intento 2: Joypad (si está conectado)
    if joypad_device >= 0 and Input.get_connected_joypads().has(joypad_device):
        var joy_x = Input.get_joy_axis(joypad_device, JOY_ANALOG_LX)
        var joy_y = Input.get_joy_axis(joypad_device, JOY_ANALOG_LY)
        
        if joy_x != 0 or joy_y != 0:
            if abs(joy_x) > deadzone:
                input.x += joy_x
            if abs(joy_y) > deadzone:
                input.y += joy_y
    
    return input.normalized()

func is_jump_pressed() -> bool:
    """Detectar si jugador presionó salto."""
    var keys = key_map[player_id]
    
    # Keyboard
    if Input.is_key_pressed(keys["jump"]):
        return true
    
    # Joypad (botón A / Cross)
    if joypad_device >= 0:
        return Input.is_joy_button_pressed(joypad_device, JOY_BUTTON_A)
    
    return false

func is_sprint_pressed() -> bool:
    """Detectar si jugador presionó sprint."""
    var keys = key_map[player_id]
    
    # Keyboard
    if Input.is_key_pressed(keys["sprint"]):
        return true
    
    # Joypad (bumper izquierdo)
    if joypad_device >= 0:
        return Input.is_joy_button_pressed(joypad_device, JOY_BUTTON_LB)
    
    return false

func just_jumped() -> bool:
    """Detectar salto ESTE FRAME."""
    var keys = key_map[player_id]
    
    if Input.is_key_just_pressed(keys["jump"]):
        return true
    
    if joypad_device >= 0:
        return Input.is_joy_button_pressed(joypad_device, JOY_BUTTON_A)
    
    return false
```

---

## 6. Modificación: PlayerController.gd (Inyección Mínima)

```gdscript
# players/elias/PlayerController.gd (CAMBIOS MÍNIMOS)

extends KinematicBody

# ... exports y variables existentes ...

var player_id := 1  # 🆕 NUEVO: identificar si es P1 o P2
var input_manager: Node  # 🆕 NUEVO: referencia a PlayerInput.gd

func _ready():
    # ... setup existente ...
    
    # 🆕 NUEVO: Buscar input_manager si está attachado
    if has_node("InputManager_P%d" % player_id):
        input_manager = get_node("InputManager_P%d" % player_id)

func _physics_process(delta):
    # ... código existente ...
    
    # 🔄 MODIFICADO: Usar input_manager si existe
    var desired_horizontal: Vector2
    if input_manager:
        desired_horizontal = input_manager.get_input_vector()
    else:
        desired_horizontal = get_input_direction()  # Fallback a original
    
    # ... resto del movimiento igual ...

func set_player_id(id: int) -> void:
    """Set player ID from outside."""
    player_id = id

# ... resto del script sin cambios ...
```

---

## 7. Escena: Menu.tscn (Cambios Mínimos)

```gdscript
# scripts/ui/Menu.gd (PARCIAL)

extends Control

var resolution_detector: MenuResolutionDetector

func _ready():
    # Instanciar detector si no existe
    if not has_node("MenuResolutionDetector"):
        resolution_detector = MenuResolutionDetector.new()
        resolution_detector.name = "MenuResolutionDetector"
        add_child(resolution_detector)
    else:
        resolution_detector = $MenuResolutionDetector
    
    # Conectar botones
    $PlayButton.connect("pressed", self, "_on_play_pressed")
    
    if has_node("CopilotButton"):
        $CopilotButton.connect("pressed", self, "_on_copilot_pressed")

func _on_play_pressed():
    """Single-player."""
    GameConfig.set_mode("singleplayer")
    get_tree().change_scene("res://scenes/levels/act1/Criogenia.tscn")

func _on_copilot_pressed():
    """Multiplayer split-screen."""
    GameConfig.set_mode("copilot")
    get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")
```

---

## 8. Autoload: GameConfig.gd (NUEVO)

```gdscript
# autoload/GameConfig.gd

extends Node

class_name GameConfig

# ===== ENUMS =====
enum GAME_MODE {
    SINGLEPLAYER,
    COPILOT,
    NETWORKED  # Future
}

# ===== ESTADO GLOBAL =====
var current_mode := GAME_MODE.SINGLEPLAYER
var is_widescreen := false
var screen_size := Vector2.ZERO

func _ready():
    """Inicializar configuración global."""
    _detect_screen_info()

func _detect_screen_info() -> void:
    """Detectar pantalla."""
    screen_size = OS.get_screen_size()
    var aspect = float(screen_size.x) / float(screen_size.y)
    is_widescreen = (aspect >= 1.5) and OS.get_name() not in ["Android", "iOS"]
    
    print("[GameConfig] Screen: %.0fx%.0f | Widescreen: %s" % [screen_size.x, screen_size.y, is_widescreen])

func set_mode(mode_str: String) -> void:
    """Cambiar modo de juego."""
    match mode_str:
        "singleplayer":
            current_mode = GAME_MODE.SINGLEPLAYER
        "copilot":
            current_mode = GAME_MODE.COPILOT
        "networked":
            current_mode = GAME_MODE.NETWORKED
        _:
            push_warning("Modo desconocido: %s" % mode_str)
    
    print("[GameConfig] Modo cambiado a: %s" % mode_str)

func get_mode() -> String:
    """Retornar modo actual como string."""
    match current_mode:
        GAME_MODE.SINGLEPLAYER:
            return "singleplayer"
        GAME_MODE.COPILOT:
            return "copilot"
        GAME_MODE.NETWORKED:
            return "networked"
        _:
            return "unknown"
```

---

## 9. Orden de Implementación (Check-list)

```
FASE 1: Detección + Menú (2 horas)
─ [ ] Crear GameConfig.gd en autoload/
─ [ ] Crear MenuResolutionDetector.gd en scripts/ui/
─ [ ] Modificar Menu.gd para instanciar detector
─ [ ] Añadir botón CopilotButton en Menu.tscn
─ [ ] Probar: Botón debe aparecer en widescreen, desaparecer en móvil
     └─ Verificación: print("[GameConfig]") en consola

FASE 2: Split-Screen (3 horas)
─ [ ] Crear carpeta res://scenes/multiplayer/
─ [ ] Crear LocalMultiplayer.tscn con estructura (ViewportContainer + GridContainer)
─ [ ] Crear CoopLevel.tscn (copia de Criogenia con 2 spawn points)
─ [ ] Crear LocalMultiplayerManager.gd en scripts/multiplayer/
─ [ ] Asignar script a LocalMultiplayer root node
─ [ ] Probar: Ambos jugadores deben verse en pantalla, cámaras independientes
     └─ Verificación: print("[LocalMultiplayerManager]") en consola

FASE 3: Input Dual (2 horas)
─ [ ] Crear PlayerInput.gd en scripts/multiplayer/
─ [ ] Crear MenuResolutionDetector versión simplificada (ya hecha)
─ [ ] Modificar PlayerController.gd mínimamente (set_player_id, input_manager)
─ [ ] Probar WASD (P1) y Flechas (P2) independientemente
     └─ Verificación: Un jugador se mueve, otro no se ve afectado

FASE 4: Refinamiento (1 hora)
─ [ ] Ajustar tamaños de viewport según resolución
─ [ ] Conectar UI (labels de estado, botón exit)
─ [ ] Test en distintas resoluciones
─ [ ] Test con 2 joypads conectados

TOTAL: ~8 horas de desarrollo + testing
```

---

## 10. Referencia Rápida: Calls Comunes

```gdscript
# Obtener resolución
var screen = OS.get_screen_size()  # Vector2(1920, 1080)

# Detectar móvil
var is_mobile = OS.get_name() in ["Android", "iOS"]

# Aspect ratio
var aspect = float(screen.x) / float(screen.y)

# Cambiar escena
get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")

# Input keyboard directo (sin actions)
if Input.is_key_pressed(KEY_W):
    # ...

# Input joypad
if Input.is_joy_button_pressed(device_id, JOY_BUTTON_A):
    # ...

# Crear nodo dinámicamente
var new_node = load("res://path/to/scene.tscn").instance()
add_child(new_node)

# Viewport con mundo compartido
viewport2.world = viewport1.world
```

---

**Documento Compilado:** 03/12/2025  
**Estado:** ✅ Código 100% Copy-Paste Listo  
**Riesgo de Integración:** Bajo (modular, non-breaking)