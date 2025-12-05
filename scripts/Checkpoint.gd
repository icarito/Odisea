extends Area

export (bool) var one_shot := true
var _activated := false

func _ready() -> void:
	connect("body_entered", self, "_on_body_entered")

func _on_body_entered(body: Object) -> void:
	if _activated and one_shot:
		return
	if typeof(PlayerManager) != TYPE_NIL and PlayerManager and PlayerManager.is_spawned():
		var p := PlayerManager.get_player()
		if is_instance_valid(p) and body == p:
			PlayerManager.set_respawn_point(global_transform)
			_activated = true
