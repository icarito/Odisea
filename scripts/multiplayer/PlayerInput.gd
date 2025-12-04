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
        return Input.is_joy_button_just_pressed(joypad_device, JOY_BUTTON_A)

    return false
