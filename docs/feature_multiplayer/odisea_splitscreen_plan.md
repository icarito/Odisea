# Plan Split-Screen (Pendiente Reimplementación)

Nota: Este plan debe actualizarse a `core` usando `InputProvider` y `SessionManager` multi-dispositivo. Ver `docs/feature_multiplayer/README.md`.

# Plan de Implementación: Split-Screen Local Multiplayer + Netplay
## Godot 3.6.2 | Arquitectura Modular para Odisea

**Fecha:** 03/12/2025 | **Resolución Base:** 640 x 480 | **Objetivo:** Detectar widescreen (>16:9) y añadir modo cooperativo

---

## 📋 Tabla de Contenidos

1. [Análisis de Requisitos](#1-análisis-de-requisitos)
2. [Arquitectura Modular Propuesta](#2-arquitectura-modular-propuesta)
3. [Detección de Resolución y Widescreen](#3-detección-de-resolución-y-widescreen)
4. [Implementación de Split-Screen](#4-implementación-de-split-screen)
5. [Sistema de Input para 2 Joysticks](#5-sistema-de-input-para-2-joysticks)
6. [Addons Recomendados](#6-addons-recomendados)
7. [Multiplayer en Red (Opcional)](#7-multiplayer-en-red-opcional)
8. [Desafíos y Soluciones](#8-desafíos-y-soluciones)
9. [Cronograma de Implementación](#9-cronograma-de-implementación)

---

## 1. Análisis de Requisitos

### Objetivo Principal
Implementar un sistema **modular** que permita:
- ✅ Detectar automáticamente si pantalla es widescreen (no móvil)
- ✅ Si widescreen: Mostrar botón "Copilot/Local Multiplayer" en Menu.tscn
- ✅ Si móvil: No mostrar opción (skipear automáticamente)
- ✅ Al iniciar modo copilot: Escena alternativa con 2 viewports side-to-side
- ✅ Player 1: WASD + botones configurable
- ✅ Player 2: Flechas OR Joypad/Joycon 2
- ✅ **Sin romper existente**: Todo debe ser opt-in y reutilizar PlayerController

### Restricciones Técnicas
- Motor: Godot 3.6.2 (KinematicBody, no CharacterBody3D)
- Render: GLES2 (sin material heavy)
- Plataformas: Linux/X11 + Android
- Resolución base: 640x480 (pero escala a widescreen)

---

## 2. Arquitectura Modular Propuesta

### 2.1 Estructura de Carpetas (Nueva)

```
res://
├── scenes/
│   ├── common/
│   │   └── (existente)
│   ├── levels/
│   │   └── (existente)
│   ├── ui/
│   │   ├── Menu.tscn (MODIFICADO: detectar widescreen + botón copilot)
│   │   └── (existente)
│   └── multiplayer/                  # 🆕 NUEVA CARPETA
│       ├── LocalMultiplayer.tscn     # Escena raíz con 2 viewports
│       ├── SplitScreenViewport.tscn  # Componente reutilizable (VP left/right)
│       ├── LocalMultiplayerUI.tscn   # HUD para modo copilot
│       └── CoopLevel.tscn            # Nivel compartido (ambos jugadores)
├── scripts/
│   ├── ui/
│   │   ├── Menu.gd (MODIFICADO)
│   │   └── MenuResolutionDetector.gd # 🆕 Lógica de detección
│   ├── multiplayer/                  # 🆕 NUEVA CARPETA
│   │   ├── LocalMultiplayerManager.gd
│   │   ├── SplitScreenController.gd
│   │   ├── PlayerInput.gd            # Sistema genérico de input (P1/P2)
│   │   └── CoopGameManager.gd
│   └── (existente)
├── autoload/
│   ├── PlayerManager.gd (MODIFICADO: soportar 2 jugadores)
│   ├── AudioManager.gd
│   └── GameConfig.gd                 # 🆕 Configuración global (resolución, modo)
└── (resto igual)
```

### 2.2 Flujo de Decisión (Árbol)

```
┌─ Inicio Godot
│  └─ Menu.tscn carga
│     ├─ MenuResolutionDetector._ready()
│     │  ├─ screen_size = OS.get_screen_size()
│     │  ├─ aspect_ratio = screen_size.x / screen_size.y
│     │  └─ is_widescreen = aspect_ratio >= 1.5 && is_not_mobile
│     │
│     ├─ Si is_widescreen:
│     │  └─ Mostrar botón "Copilot Mode" en Menu.tscn
│     │     ├─ Al pulsar:
│     │     │  ├─ GameConfig.set_mode("copilot")
│     │     │  └─ get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")
│     │     │
│     │     └─ LocalMultiplayer._ready()
│     │        ├─ Instancia CoopLevel (compartido)
│     │        ├─ Crea 2 SplitScreenViewports (left/right)
│     │        ├─ Asigna PlayerController_P1 → VP_left
│     │        ├─ Asigna PlayerController_P2 → VP_right
│     │        ├─ Inicializa input para P1 (WASD) y P2 (Flechas/Joypad)
│     │        └─ Inicia gameplay
│     │
│     └─ Si NOT widescreen:
│        └─ Solo botón "Play" (modo single-player existente)
```

---

## 3. Detección de Resolución y Widescreen

### 3.1 Script: `MenuResolutionDetector.gd`

```gdscript
# scripts/ui/MenuResolutionDetector.gd

extends Node

class_name MenuResolutionDetector

# ===== CONFIGURACIÓN =====
export var min_aspect_ratio_for_widescreen := 1.5  # 16:10 o mayor
export var mobile_max_screen_size := Vector2(1024, 768)  # iPad max

# ===== DETECCIÓN =====
var is_widescreen := false
var is_mobile := false
var screen_size := Vector2.ZERO
var aspect_ratio := 0.0

func _ready():
    """Detectar resolución y tipo de pantalla al iniciar."""
    _detect_screen_info()
    _set_button_visibility()

func _detect_screen_info() -> void:
    """Obtener tamaño de pantalla y calcular aspect ratio."""
    screen_size = OS.get_screen_size()
    
    # Calcular aspect ratio
    aspect_ratio = float(screen_size.x) / float(screen_size.y)
    
    # Detectar si es móvil (heurística simple)
    # En Android: pantalla típica ≤ 720 altura o aspect ratio específicos
    is_mobile = _is_mobile_device()
    
    # Determinar si es widescreen
    is_widescreen = (aspect_ratio >= min_aspect_ratio_for_widescreen) and not is_mobile
    
    # Debug
    print("[MenuResolutionDetector] Screen: %.0f x %.0f" % [screen_size.x, screen_size.y])
    print("[MenuResolutionDetector] Aspect Ratio: %.2f" % aspect_ratio)
    print("[MenuResolutionDetector] Mobile: %s | Widescreen: %s" % [is_mobile, is_widescreen])

func _is_mobile_device() -> bool:
    """Detectar si el dispositivo es móvil."""
    # Método 1: Verificar SO
    if OS.get_name() in ["Android", "iOS", "HTML5"]:
        return true
    
    # Método 2: Heurística de tamaño
    # Pantallas móviles típicamente tienen altura ≤ 1080
    if screen_size.y <= 1080 and screen_size.x <= 1080:
        return true
    
    return false

func _set_button_visibility() -> void:
    """Mostrar/ocultar botón de Copilot según detección."""
    # Obtener referencia al menú padre
    var menu = get_parent()
    
    if not menu.has_node("CopilotButton"):
        push_warning("[MenuResolutionDetector] CopilotButton no encontrado en Menu")
        return
    
    var copilot_btn = menu.get_node("CopilotButton")
    
    # Mostrar solo si es widescreen
    copilot_btn.visible = is_widescreen
    copilot_btn.disabled = not is_widescreen
    
    # Tooltip
    if is_widescreen:
        copilot_btn.hint_tooltip = "Jugar en modo cooperativo (2 controladores)"
    else:
        copilot_btn.hint_tooltip = "Modo cooperativo no disponible en esta resolución"

func get_multiplayer_mode() -> String:
    """Retornar modo recomendado: 'singleplayer' o 'copilot'."""
    return "copilot" if is_widescreen else "singleplayer"
```

### 3.2 Modificación: `Menu.gd`

```gdscript
# scripts/ui/Menu.gd (PARCIAL - lo que cambia)

extends Control

var resolution_detector: MenuResolutionDetector

func _ready():
    resolution_detector = $MenuResolutionDetector  # Instancia el detector
    
    # Conectar botones existentes
    $PlayButton.connect("pressed", self, "_on_play_pressed")
    
    # Conectar botón de copilot (NUEVO)
    if has_node("CopilotButton"):
        $CopilotButton.connect("pressed", self, "_on_copilot_pressed")

func _on_play_pressed():
    """Flujo single-player (existente)."""
    GameConfig.set_mode("singleplayer")
    get_tree().change_scene("res://scenes/levels/act1/Criogenia.tscn")

func _on_copilot_pressed():
    """Flujo copilot/multiplayer (NUEVO)."""
    GameConfig.set_mode("copilot")
    get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")
```

---

## 4. Implementación de Split-Screen

### 4.1 Escena: `LocalMultiplayer.tscn`

**Estructura de nodos:**

```
LocalMultiplayer (Node)
├── GameManager.gd (script: LocalMultiplayerManager)
├── ViewportContainer (Control)
│   ├── GridContainer (2 columns)
│   │   ├── SplitScreenViewport_P1 (ViewportContainer)
│   │   │   └── Viewport_P1 (Viewport)
│   │   │       ├── CoopLevel (instance)
│   │   │       ├── PlayerController_P1 (instance)
│   │   │       └── Camera_P1 (Camera3D)
│   │   │
│   │   └── SplitScreenViewport_P2 (ViewportContainer)
│   │       └── Viewport_P2 (Viewport)
│   │           ├── (ref a nivel compartido)
│   │           ├── PlayerController_P2 (instance)
│   │           └── Camera_P2 (Camera3D)
│   │
│   └── UI_Copilot (CanvasLayer)
│       ├── Label_P1_Info
│       ├── Label_P2_Info
│       └── ExitButton
```

### 4.2 Script: `LocalMultiplayerManager.gd`

```gdscript
# scripts/multiplayer/LocalMultiplayerManager.gd

extends Node

class_name LocalMultiplayerManager

# ===== REFERENCIAS =====
var player1: Node
var player2: Node
var level: Node
var viewport_p1: Viewport
var viewport_p2: Viewport
var camera_p1: Camera3D
var camera_p2: Camera3D

# ===== CONFIG =====
export var shared_world := true  # Ambos jugadores en el mismo mundo

func _ready():
    """Inicializar el modo copilot."""
    _setup_level()
    _setup_viewports()
    _setup_players()
    _setup_cameras()
    _setup_input()

func _setup_level() -> void:
    """Instanciar el nivel compartido."""
    var level_scene = load("res://scenes/multiplayer/CoopLevel.tscn")
    if not level_scene:
        push_error("No se pudo cargar CoopLevel.tscn")
        return
    
    level = level_scene.instance()
    add_child(level)
    print("[LocalMultiplayerManager] Nivel cargado")

func _setup_viewports() -> void:
    """Configurar viewports para split-screen."""
    viewport_p1 = get_node("ViewportContainer/GridContainer/SplitScreenViewport_P1/Viewport_P1")
    viewport_p2 = get_node("ViewportContainer/GridContainer/SplitScreenViewport_P2/Viewport_P2")
    
    if shared_world:
        # Compartir mundo entre viewports
        viewport_p2.world = viewport_p1.world
    
    # Ajustar tamaño de viewport
    var screen_size = OS.get_screen_size()
    var half_width = int(screen_size.x / 2)
    var height = int(screen_size.y)
    
    viewport_p1.size = Vector2(half_width, height)
    viewport_p2.size = Vector2(half_width, height)
    
    print("[LocalMultiplayerManager] Viewports configurados: %dx%d cada uno" % [half_width, height])

func _setup_players() -> void:
    """Instanciar y posicionar jugadores."""
    # Player 1 (izquierda)
    player1 = load("res://players/elias/Pilot.tscn").instance()
    player1.name = "Player_1"
    viewport_p1.add_child(player1)
    player1.global_transform.origin = Vector3(-5, 0, 0)
    
    # Player 2 (derecha)
    player2 = load("res://players/elias/Pilot.tscn").instance()
    player2.name = "Player_2"
    viewport_p2.add_child(player2)
    player2.global_transform.origin = Vector3(5, 0, 0)
    
    # Asignar IDs
    player1.player_id = 1
    player2.player_id = 2
    
    print("[LocalMultiplayerManager] Jugadores instanciados")

func _setup_cameras() -> void:
    """Crear cámaras para cada viewport."""
    camera_p1 = Camera3D.new()
    camera_p1.name = "Camera_P1"
    player1.add_child(camera_p1)
    camera_p1.make_current()
    
    # Nota: Camera_P2 se crea en viewport_p2 y apunta a player2
    camera_p2 = Camera3D.new()
    camera_p2.name = "Camera_P2"
    player2.add_child(camera_p2)

func _setup_input() -> void:
    """Inicializar sistema de input para P1 y P2."""
    # Esto se integra con PlayerInput.gd en cada controlador
    print("[LocalMultiplayerManager] Input configurado")

func _process(delta):
    """Actualizar cámaras cada frame."""
    if player1:
        camera_p1.global_transform.origin = player1.global_transform.origin + Vector3(0, 2, 5)
        camera_p1.look_at(player1.global_transform.origin, Vector3.UP)
    
    if player2:
        camera_p2.global_transform.origin = player2.global_transform.origin + Vector3(0, 2, 5)
        camera_p2.look_at(player2.global_transform.origin, Vector3.UP)

func _on_exit_pressed():
    """Volver al menú."""
    get_tree().change_scene("res://scenes/ui/Menu.tscn")
```

---

## 5. Sistema de Input para 2 Joysticks

### 5.1 Script: `PlayerInput.gd`

```gdscript
# scripts/multiplayer/PlayerInput.gd

extends Node

class_name PlayerInput

# ===== CONFIG POR JUGADOR =====
export var player_id := 1  # 1 o 2
export var use_keyboard := true
export var use_joypad := true

# ===== MAPEO DE ACCIONES =====
var action_map = {
    "forward": "forward_%d",
    "back": "back_%d",
    "left": "left_%d",
    "right": "right_%d",
    "jump": "jump_%d",
    "sprint": "sprint_%d",
}

# ===== REFERENCIA A CONTROLADOR =====
var player_controller: Node

func _ready():
    """Validar que exista PlayerController en el padre."""
    if player_id < 1 or player_id > 2:
        push_error("[PlayerInput] player_id inválido: %d" % player_id)
        return
    
    player_controller = get_parent() if get_parent() is Node else null
    
    if not player_controller:
        push_warning("[PlayerInput] No se encontró PlayerController en padre")

func get_input_vector() -> Vector2:
    """Obtener vector de movimiento (forward/back, left/right)."""
    var input = Vector2.ZERO
    
    # Intento 1: Actions genéricas nombradas
    var forward_key = action_map["forward"] % player_id  # "forward_1" o "forward_2"
    var back_key = action_map["back"] % player_id
    var left_key = action_map["left"] % player_id
    var right_key = action_map["right"] % player_id
    
    if use_keyboard and InputMap.has_action(forward_key):
        if Input.is_action_pressed(forward_key):
            input.y -= 1
        if Input.is_action_pressed(back_key):
            input.y += 1
        if Input.is_action_pressed(left_key):
            input.x -= 1
        if Input.is_action_pressed(right_key):
            input.x += 1
    
    # Intento 2: Joystick analógico si disponible
    if use_joypad:
        var joy_input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        # Filtrar por device_id del joypad
        # Nota: Esto es simplificado; Godot 3 requiere manejo especial
        if joy_input.length() > 0.1:
            input = input.lerp(joy_input, 0.5)
    
    return input.normalized()

func is_jump_pressed() -> bool:
    """Detectar si jugador presionó salto."""
    var jump_key = action_map["jump"] % player_id
    return InputMap.has_action(jump_key) and Input.is_action_just_pressed(jump_key)

func is_sprint_pressed() -> bool:
    """Detectar si jugador presionó sprint."""
    var sprint_key = action_map["sprint"] % player_id
    return InputMap.has_action(sprint_key) and Input.is_action_pressed(sprint_key)
```

### 5.2 Configuración de Project Settings (Input Map)

**En `project.godot`, añadir estas acciones:**

```ini
[input]

forward_1={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":87,"unicode":0,"echo":false,"script":null) ]
}
back_1={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":83,"unicode":0,"echo":false,"script":null) ]
}
left_1={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":65,"unicode":0,"echo":false,"script":null) ]
}
right_1={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":68,"unicode":0,"echo":false,"script":null) ]
}
jump_1={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":32,"unicode":0,"echo":false,"script":null) ]
}

# Player 2: Flechas
forward_2={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":16777232,"unicode":0,"echo":false,"script":null) ]
}
back_2={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":16777234,"unicode":0,"echo":false,"script":null) ]
}
left_2={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":16777231,"unicode":0,"echo":false,"script":null) ]
}
right_2={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":16777233,"unicode":0,"echo":false,"script":null) ]
}
jump_2={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":13,"unicode":0,"echo":false,"script":null) ]
}

# También agregar Joypad (botones estándar)
forward_1={
"events": [ Object(InputEventJoypadButton,"resource_local_to_scene":false,"device":0,"button_index":12) ]
}
# ... más mappings de joypad
```

---

## 6. Addons Recomendados

### 6.1 Addons Prioritarios

| Addon | Propósito | Instalación | Impacto |
|-------|----------|-------------|---------|
| **Input Map Manager** | UI para mapear inputs sin editar project.godot | Asset Libre | ALTO |
| **Multiplayer Synchronizer Framework** | Helper para sincronizar estado en red | Custom/Asset | ALTO |
| **Simple State Machine** | FSM limpia para estados de jugador | GDScript puro | MEDIO |
| **Signal Debugger** | Inspeccionar signals en runtime | Plugin editor | BAJO |

### 6.2 Alternativa: Sin Addons (Recomendado para MVP)

Tu proyecto actual **ya tiene lo necesario**. Los addons serían nice-to-have:

- ✅ **Godot 3.6 built-in**: MultiplayerAPI, Viewport, Input system
- ✅ **Tu codebase**: PlayerController, AnimationTree, Conveyor
- ✅ **A implementar**: Solo scripts GDScript nuevos (PlayerInput, LocalMultiplayerManager)

---

## 7. Multiplayer en Red (Opcional)

### 7.1 Arquitectura High-Level (Godot 3.x)

```
┌─ LocalMultiplayer.tscn (single screen)
│
└─ NetworkedMultiplayer.tscn (con sincronización)
   ├─ MultiplayerAPI (ENetMultiplayerPeer)
   │  ├─ Server (Godot 3: uno de los clientes es "servidor")
   │  └─ Clients (conectan al servidor)
   │
   ├─ MultiplayerSpawner (autoridad del servidor)
   ├─ MultiplayerSynchronizer (sincroniza posiciones)
   └─ RPC calls (acciones de jugadores)
```

### 7.2 Desafíos Clave

| Desafío | Causa | Solución | Complejidad |
|---------|-------|----------|-------------|
| **Lag de movimiento** | Red latency 50-200ms | Prediction + client-side input | ALTA |
| **Sincronización de viewport** | 2 cámaras distintas | Enviar transform de cámaras | MEDIA |
| **Input divergence** | Clientes presionan botones distintos | RPC de acciones, no posiciones | MEDIA |
| **Pause/Unpause remoto** | Un jugador pausa, otro no se entera | Señal multiplayer de estado | BAJA |

### 7.3 Recomendación: Fases

**MVP (Actual):**
- Local multiplayer solo (split-screen)
- Sin red

**Fase 2 (Post-MVP):**
- Agregar sincronización de red mediante ENetMultiplayerPeer
- Validar en LAN local

**Fase 3 (Futuro):**
- Matchmaking online (Steamworks o custom server)

---

## 8. Desafíos y Posibles Soluciones

### 8.1 Desafío: Dos Cámaras, un Mundo

**Problema:** Split-screen requiere 2 cámaras independientes renderizando el mismo mundo simultáneamente.

**Soluciones:**
1. **Usar 2 Viewports** (recomendado para MVP)
   - Cada viewport tiene su propia Camera3D
   - Comparten el mismo 3D World
   - Costo: ~150% FPS vs single camera

2. **Usar 1 ViewportTexture + Quad** (avanzado)
   - Render a texturas, mostrar en UI
   - Mayor control sobre efectos visuales

### 8.2 Desafío: Input Conflict

**Problema:** Si Player 1 usa WASD y Player 2 flechas, pueden colisionar si están en la misma escena.

**Soluciones:**
1. **Namespace de acciones** (actual)
   - `forward_1`, `forward_2`, etc.
   - Cada PlayerController escucha su propio namespace

2. **Device-based filtering**
   ```gdscript
   func _input(event: InputEvent):
       if event.device != player_device_id:
           return
   ```

### 8.3 Desafío: Rendimiento en GLES2

**Problema:** Dos viewports × 60 FPS = 120 rendercalls potenciales.

**Soluciones:**
1. **Reducir a 30 FPS en móvil**
   - Project settings: `display/window/vsync/use_vsync = true`

2. **Shared geometry**
   - Plataformas, enemigos, etc. son `StaticBody`/`RigidBody`, no duplicados

3. **LOD (Level of Detail)**
   - Distancia > 20m → reducir detalles

### 8.4 Desafío: Sincronización en Red (Latency)

**Problema:** Si jugador 1 salta en PC y jugador 2 en móvil via internet, lag de 100ms desincroniza saltos.

**Soluciones (Godot 3.x):**
1. **Authority Model**
   - Server simula física
   - Clientes predecen, server corrige cada 100ms

2. **RPC-based Actions**
   ```gdscript
   @rpc("any_peer", "call_local")
   func perform_jump():
       # Cualquier cliente llama esto
       # Server ejecuta autoritariamente
   ```

3. **NetworkSynchronizer (Godot 4+)**
   - En 3.x: usar MultiplayerAPI + tween manualmente

---

## 9. Cronograma de Implementación

### Fase 1: Detección y Menú (Día 1-2)
- [ ] Crear `MenuResolutionDetector.gd`
- [ ] Modificar `Menu.gd` para mostrar botón Copilot
- [ ] Probar en desktop y Android
- **Verificación:** Botón aparece en 16:9, no en móvil

### Fase 2: Split-Screen (Día 3-4)
- [ ] Crear `LocalMultiplayer.tscn` con 2 Viewports
- [ ] Implementar `LocalMultiplayerManager.gd`
- [ ] Duplicar PlayerController para P1 y P2
- [ ] Crear `CoopLevel.tscn` (compartido)
- **Verificación:** Ambos jugadores visibles, movimiento independiente

### Fase 3: Input Dual (Día 5-6)
- [ ] Crear `PlayerInput.gd`
- [ ] Mapear acciones en Project Settings (P1: WASD, P2: Flechas)
- [ ] Integrar PlayerInput en ambos controladores
- [ ] Probar con 2 teclados conectados
- **Verificación:** WASD mueve P1, Flechas mueven P2

### Fase 4: Polish y QA (Día 7)
- [ ] Ajustar tamaños de viewport
- [ ] HUD de copilot (info jugadores)
- [ ] Botón de salida a menú
- [ ] Test en distintas resolucionesResolution
- **Entregable:** Build split-screen funcional

### Fase 5 (Opcional): Red (Post-MVP)
- [ ] Investigar ENetMultiplayerPeer
- [ ] Estructura NetworkedMultiplayer.tscn
- [ ] RPC de acciones (no posiciones)
- [ ] Test LAN local

---

## 10. Referencias Documentadas

### Videos (Godot 3.x)
- **[web:113]** "How to Easily Add Split Screen Multiplayer in Godot" (2022)
  → Viewport + GridContainer básico
- **[web:116]** "Godot 3.0: Splitscreen Multiplayer" (2018)
  → KidsCanCode tutorial completo
- **[web:119]** "How to do a Split Screen Co-op in Godot" (2022)
  → GDQuest, enfocado en gameplay

### Documentación Oficial
- **[web:114]** Godot Docs: "Multiple resolutions"
  → Aspect ratio, stretch mode
- **[web:118]** Godot Docs: "Controllers, gamepads, joysticks"
  → Input.get_vector(), Input.is_joy_button_pressed()
- **[web:130]** Godot Docs: "High-level multiplayer"
  → ENetMultiplayerPeer, RPC, autoridad

### Forums y Comunidad
- **[web:117]** Forum: "Screen resolutions and viewport scaling"
  → OS.get_screen_size() quirks
- **[web:121]** Reddit: "Best Way To Handle Controller Input"
  → Device-based input filtering
- **[web:138]** Forum: "Split-Screen Networked Multiplayer"
  → Gotchas de sincronizar viewports en red

### Detección de Resolución
- **[web:120]** Reddit: "Get screen resolution from GDScript"
  → OS.get_window_size() vs OS.get_screen_size()
- **[web:132]** Forum: "OS.get_screen_size()"
  → HiDPI considerations

---

## Conclusión

**Recomendación Final:**

1. **MVP Local (Semana 1):**
   - Split-screen local sin red
   - Detección widescreen automática
   - Input dual (WASD + Flechas)
   - Reutilizar PlayerController existente

2. **Por qué es viable:**
   - Godot 3.6 ya tiene todo (Viewport, MultiplayerAPI, Input)
   - Tu codebase ya está modular (PlayerController, AnimationTree)
   - No necesitas addons costosos
   - Escalable a red después sin refactor mayor

3. **Desafíos principales:**
   - Rendimiento GLES2: 2 viewports en Android
   - Input handling: namespace de acciones por jugador
   - Net sync: lag predictor para saltos/plataformas

**Próximo Paso:** Comenzar con Fase 1 (detección + menú) para validar que la arquitectura no rompe lo existente.

---

**Documento Compilado:** 03/12/2025  
**Estado:** ✅ Listo para implementación  
**Complejidad:** Media | **Riesgo:** Bajo (modular, opt-in)