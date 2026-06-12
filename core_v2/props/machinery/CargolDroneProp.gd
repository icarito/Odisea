extends Spatial

# CargolDroneProp.gd
# PropZoo-compatible wrapper for CargolDroneV2.
# Responds to set_active(true/false) from the exhibit lever:
#   - Activated: Drone follows the player
#   - Deactivated: Drone returns to its starting position (exhibit)

export(float) var follow_distance := 3.0
export(float) var hover_height := 3.0

var is_active := false
var _drone = null # CargolDroneV2
var _home_position := Vector3.ZERO

signal activated()
signal deactivated()

func _ready():
	# Find the CargolDroneV2 child
	_drone = _find_drone(self)
	if _drone:
		# Record home as the drone's starting global position
		# (deferred so transforms are resolved)
		call_deferred("_cache_home_position")
	else:
		printerr("[CargolDroneProp] No CargolDroneV2 child found!")

func _cache_home_position():
	if _drone:
		_home_position = _drone.global_transform.origin

func set_active(value: bool, _immediate: bool = false) -> void:
	if is_active == value:
		return
	is_active = value

	if is_active:
		_activate()
		emit_signal("activated")
	else:
		_deactivate()
		emit_signal("deactivated")

func interact() -> void:
	set_active(not is_active)

func _activate():
	if not _drone:
		return
	var player = _find_player()
	if player:
		_drone.follow_target(player, follow_distance)
	else:
		printerr("[CargolDroneProp] Player not found for follow_target")

func _deactivate():
	if not _drone:
		return
	_drone.return_to(_home_position)

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if not players.empty():
		return players[0]
	var root = get_tree().current_scene
	if root:
		var pilot = root.find_node("Pilot", true, false)
		if pilot:
			return pilot
	return null

func _find_drone(node: Node):
	"""Recursively find CargolDroneV2 among children."""
	for child in node.get_children():
		if child is CargolDroneV2:
			return child
		var found = _find_drone(child)
		if found:
			return found
	return null
