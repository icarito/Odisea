extends HoldInteractableV2
class_name PressurePump

# PressurePump.gd — bomba manual de presión (FD-258).
#
# El primer mecanismo de "mantener presionado" del proyecto: mientras el jugador sostiene
# la interacción, el pistón baja y la presión del sector sube. Al soltar, el pistón vuelve.
# No es una palanca: el esfuerzo dura, y se ve durar.

# Recorrido del pistón, en metros, entre reposo y presionado del todo.
export(float) var piston_travel: float = 0.22

onready var _piston: Spatial = get_node_or_null("Piston")
var _piston_rest_y: float = 0.0


func _ready() -> void:
	._ready()
	interaction_text = "Bombear"
	if _piston:
		_piston_rest_y = _piston.translation.y


func _update_hold_visuals(progress: float) -> void:
	if _piston:
		_piston.translation.y = _piston_rest_y - piston_travel * progress
