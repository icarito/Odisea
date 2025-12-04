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
    is_widescreen = GameConfig.is_widescreen
    _set_button_visibility()

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
