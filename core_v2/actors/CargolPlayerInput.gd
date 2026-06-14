extends Node

# CargolPlayerInput.gd - Command layer for CargolDroneV2

onready var drone = get_parent()

var _is_c_held := false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cargol_command"):
		_is_c_held = true
	elif event.is_action_released("cargol_command"):
		if _is_c_held:
			_on_c_tapped()
		_is_c_held = false

	if _is_c_held and event.is_action_pressed("interact"):
		_on_c_plus_e()
		# Prevent tap on release
		_is_c_held = false
		get_tree().set_input_as_handled()

func _on_c_tapped() -> void:
	var target_pos = _get_raycast_target()
	if target_pos != Vector3.ZERO:
		drone.move_to(target_pos)
	else:
		_toggle_follow()

func _on_c_plus_e() -> void:
	var cargo_info = drone.query_cargo()
	if cargo_info.get("attached", false):
		drone.release(Vector3.ZERO)
	else:
		var nearest_box = _find_nearest_in_group("pushable_box", 5.0)
		if nearest_box:
			drone.pickup(nearest_box.get_path())

func _get_raycast_target() -> Vector3:
	var camera = get_viewport().get_camera()
	if not camera: return Vector3.ZERO

	var viewport_size = get_viewport().size
	var viewport_center = viewport_size / 2.0

	var from = camera.project_ray_origin(viewport_center)
	var to = from + camera.project_ray_normal(viewport_center) * 100.0

	var space_state = drone.get_world().direct_space_state
	# Collide with environment (layer 1)
	var result = space_state.intersect_ray(from, to, [drone], 1)

	if result:
		return result.position
	return Vector3.ZERO

func _toggle_follow() -> void:
	if drone.get("_is_following_target"):
		drone.stop()
	else:
		var player = _find_player()
		if player:
			drone.follow_target(player)

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _find_nearest_in_group(group_name: String, max_dist: float) -> Spatial:
	var nodes = get_tree().get_nodes_in_group(group_name)
	var nearest = null
	var min_dist = max_dist
	var my_pos = drone.global_transform.origin

	for node in nodes:
		if node is Spatial:
			var dist = my_pos.distance_to(node.global_transform.origin)
			if dist < min_dist:
				min_dist = dist
				nearest = node
	return nearest
