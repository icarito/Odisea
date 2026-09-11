extends Node
class_name SuitOSContextDriver

# SuitOSContextDriver.gd - Read-only context driver for SuitOS / OdiseaOS (FD-296 F1.5)
# Queries player location and focused terminal state, updating SuitOS context without writing to world state.

func _physics_process(_delta: float) -> void:
	if not has_node("/root/SuitOS"):
		return

	var context: Dictionary = {
		"player_position": [0.0, 0.0, 0.0],
		"focus_id": ""
	}

	var tree = get_tree()
	if tree != null:
		var players = tree.get_nodes_in_group("player")
		if players.size() > 0:
			var p = players[0]
			if is_instance_valid(p) and p is Spatial:
				var pos: Vector3 = (p as Spatial).global_transform.origin
				context["player_position"] = [pos.x, pos.y, pos.z]

	var suit_os = get_node("/root/SuitOS")
	if suit_os.has_method("set_context"):
		suit_os.set_context(context)
