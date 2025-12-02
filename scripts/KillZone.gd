extends Area

func _ready() -> void:
	connect("body_entered", self, "_on_body_entered")

func _on_body_entered(body: Object) -> void:
	# Si el jugador cae en la zona, respawnear
	if typeof(PlayerManager) != TYPE_NIL and PlayerManager and PlayerManager.is_spawned():
		var p := PlayerManager.get_player()
		if is_instance_valid(p) and body == p:
			PlayerManager.respawn()
