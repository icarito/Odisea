extends Node

# CargolController.gd
# Links an InteractableBaseV2 (e.g. Lever) to a CargolDroneV2.
# Activate → drone follows the player.
# Deactivate → drone returns to home position.
# Attach as a child of the Lever/InteractableBaseV2 node.

export(NodePath) var drone_path
export(Vector3) var home_position = Vector3.ZERO
export(float) var follow_distance = 3.0

var _drone = null # CargolDroneV2

func _ready():
	# Resolve drone reference
	if drone_path and not drone_path.is_empty():
		_drone = get_node_or_null(drone_path)
	
	if not _drone:
		printerr("[CargolController] Drone not found at path: ", drone_path)
	
	# Connect to parent's activated/deactivated signals
	# The parent should be an InteractableBaseV2 (or InteractableBridge with sources)
	var source = _find_signal_source()
	if source:
		if source.has_signal("activated") and not source.is_connected("activated", self, "_on_activated"):
			source.connect("activated", self, "_on_activated")
		if source.has_signal("deactivated") and not source.is_connected("deactivated", self, "_on_deactivated"):
			source.connect("deactivated", self, "_on_deactivated")
		print("[CargolController] Connected to source: ", source.name)
	else:
		printerr("[CargolController] No signal source found (parent or children with activated/deactivated signals)")

func _find_signal_source() -> Node:
	"""Find the node that emits activated/deactivated signals."""
	var parent = get_parent()
	if not parent:
		return null
	
	# Check parent itself
	if parent.has_signal("activated"):
		return parent
	
	# Check parent's children (e.g. RotatingLever inside Lever)
	for child in parent.get_children():
		if child == self:
			continue
		if child.has_signal("activated"):
			return child
		# Recurse one level deeper
		for grandchild in child.get_children():
			if grandchild.has_signal("activated"):
				return grandchild
	
	return null

func _find_player() -> Node:
	"""Find the player node in the scene tree."""
	# Try the standard groups
	var players = get_tree().get_nodes_in_group("player")
	if not players.empty():
		return players[0]
	
	# Fallback: search by name
	var root = get_tree().current_scene
	if root:
		var pilot = root.find_node("Pilot", true, false)
		if pilot:
			return pilot
	
	return null

func _on_activated():
	if not _drone:
		printerr("[CargolController] _on_activated: No drone reference")
		return
	
	var player = _find_player()
	if player:
		# Updated for new AgentBase API
		_drone.follow_target(player, follow_distance)
	else:
		printerr("[CargolController] _on_activated: Player not found")

func _on_deactivated():
	if not _drone:
		printerr("[CargolController] _on_deactivated: No drone reference")
		return
	
	# Updated for new AgentBase API
	_drone.target_position = home_position
	_drone.current_state = _drone.State.RETURN_HOME
