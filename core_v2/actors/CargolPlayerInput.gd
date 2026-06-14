extends Node

# CargolPlayerInput.gd - Command layer for CargolDroneV2
# Player gives contextual orders to Cargol with C key.
# Must be a child of CargolDroneV2.

export(NodePath) var interaction_marker_path := "/root/InteractionMarker"
export(float) var command_range := 15.0

var _drone: CargolDroneV2
var _marker_system: Node
var _is_following := true
var _c_held := false

func _ready() -> void:
	_drone = get_parent() as CargolDroneV2
	_marker_system = get_node_or_null(interaction_marker_path)

func _input(event: InputEvent) -> void:
	if not _drone or event.is_echo():
		return

	if event.is_action_pressed("cargol_command"):
		_c_held = true
	elif event.is_action_released("cargol_command"):
		if _c_held:
			_on_c_tapped()
		_c_held = false

	if _c_held and event.is_action_pressed("interact"):
		_on_c_plus_e()
		_c_held = false
		get_tree().set_input_as_handled()

func _on_c_tapped() -> void:
	var target = _get_target_under_crosshair()
	if target:
		_drone.stop()
		_drone.move_to(target.global_transform.origin)
		return

	_is_following = not _is_following
	if _is_following:
		var player = _find_player()
		if player:
			_drone.follow_target(player, 3.0)
	else:
		_drone.stop()

func _on_c_plus_e() -> void:
	if _drone._attached_node:
		_drone.release(Vector3(2, 0, 0))
	else:
		var box = _find_nearest_box()
		if box:
			_drone.pickup(box.get_path())

func _get_target_under_crosshair() -> Spatial:
	var camera = get_viewport().get_camera()
	if not camera:
		return null
	var from = camera.project_ray_origin(get_viewport().size * 0.5)
	var to = from + camera.project_ray_normal(get_viewport().size * 0.5) * command_range
	var space_state = camera.get_world().direct_space_state
	var result = space_state.intersect_ray(from, to)
	if result and result.collider:
		return result.collider as Spatial
	return null

func _find_nearest_box() -> Spatial:
	var boxes = get_tree().get_nodes_in_group("pushable_box")
	var nearest: Spatial = null
	var nearest_dist := INF
	for box in boxes:
		var d = _drone.global_transform.origin.distance_to(box.global_transform.origin)
		if d < nearest_dist and d < 5.0:
			nearest_dist = d
			nearest = box
	return nearest

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if not players.empty() else null
