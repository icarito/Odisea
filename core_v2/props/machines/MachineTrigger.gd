extends Area

# FD-320: zona de un solo disparo. Emite "entered" la primera vez que entra el jugador.

signal entered()

var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # capa del jugador
	connect("body_entered", self, "_on_body_entered")


func _on_body_entered(body: Node) -> void:
	if _fired or not body.is_in_group("player"):
		return
	_fired = true
	emit_signal("entered")
