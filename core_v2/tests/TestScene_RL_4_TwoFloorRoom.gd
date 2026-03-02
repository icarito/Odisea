extends Spatial

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const GROUND_Y = 1.0
const UPPER_Y = 5.0
const STAGE_MAX_STEPS = 1500

var _randomizer: RLSceneRandomizer = null
var _didactic_mode := false

func _ready() -> void:
	_didactic_mode = _is_didactic_enabled()
	_ensure_upper_room()
	if _didactic_mode:
		_apply_didactic_geometry()
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_ensure_randomizer()
	if not _randomizer.has_pool("target_room"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()
	var ground_prob = 0.85 if _didactic_mode else 0.72
	var spawn_pool = "spawn_ground" if randf() < ground_prob else "spawn_upper"
	var pair = _randomizer.choose_episode([spawn_pool], ["target_room"], 9.0, 42.0, 200)
	if pair.empty():
		return {}
	pair["max_steps"] = max(STAGE_MAX_STEPS, 1700) if _didactic_mode else STAGE_MAX_STEPS
	return pair

func _ensure_randomizer() -> void:
	if _randomizer != null:
		return
	_randomizer = RLSceneRandomizer.new()
	_randomizer.configure(self)
	_build_pools()

func _build_pools() -> void:
	_randomizer.clear()
	if _didactic_mode:
		# Favors a ramp-up route and a larger upper target room.
		_randomizer.add_box_pool("spawn_ground", Vector3(-15.0, GROUND_Y, -15.0), Vector3(6.0, GROUND_Y, 8.0), 190, GROUND_Y, 0.38)
		_randomizer.add_box_pool("spawn_upper", Vector3(-6.0, UPPER_Y, -6.0), Vector3(6.0, UPPER_Y, 6.0), 90, UPPER_Y, 0.42)
		_randomizer.add_box_pool("target_room", Vector3(2.7, UPPER_Y, -9.6), Vector3(9.5, UPPER_Y, -3.4), 220, UPPER_Y, 0.35)
		return
	_randomizer.add_box_pool("spawn_ground", Vector3(-20.0, GROUND_Y, -20.0), Vector3(20.0, GROUND_Y, 20.0), 220, GROUND_Y, 0.45)
	_randomizer.add_box_pool("spawn_upper", Vector3(-8.0, UPPER_Y, -8.0), Vector3(8.0, UPPER_Y, 8.0), 120, UPPER_Y, 0.45)
	_randomizer.add_box_pool("target_room", Vector3(3.2, UPPER_Y, -9.0), Vector3(8.7, UPPER_Y, -4.0), 190, UPPER_Y, 0.40)

func _ensure_upper_room() -> void:
	if get_node_or_null("UpperTargetRoom") != null:
		return
	var room = Spatial.new()
	room.name = "UpperTargetRoom"
	add_child(room)
	room.add_child(_make_wall("RoomNorth", Vector3(6.0, 5.0, -10.3), Vector3(8.0, 2.4, 0.8)))
	room.add_child(_make_wall("RoomSouth", Vector3(6.0, 5.0, -2.1), Vector3(8.0, 2.4, 0.8)))
	room.add_child(_make_wall("RoomWest", Vector3(1.9, 5.0, -6.2), Vector3(0.8, 2.4, 8.6)))
	room.add_child(_make_wall("RoomEastNorth", Vector3(10.1, 5.0, -8.6), Vector3(0.8, 2.4, 2.6)))
	room.add_child(_make_wall("RoomEastSouth", Vector3(10.1, 5.0, -3.8), Vector3(0.8, 2.4, 2.6)))

func _make_wall(name: String, pos: Vector3, size: Vector3) -> StaticBody:
	var body = StaticBody.new()
	body.name = name
	body.transform.origin = pos

	var col = CollisionShape.new()
	var shape = BoxShape.new()
	shape.extents = size * 0.5
	col.shape = shape
	body.add_child(col)

	var mesh = MeshInstance.new()
	var cube = CubeMesh.new()
	cube.size = size
	mesh.mesh = cube
	body.add_child(mesh)
	return body

func _is_didactic_enabled() -> bool:
	var scene_flag = OS.get_environment("ANNA_RL_DIDACTIC_RL4")
	if scene_flag != "":
		return scene_flag.to_lower() in ["1", "true", "yes", "on"]
	var global_flag = OS.get_environment("ANNA_RL_DIDACTIC")
	if global_flag != "":
		return global_flag.to_lower() in ["1", "true", "yes", "on"]
	return false

func _apply_didactic_geometry() -> void:
	for node_name in [
		"Obstacle_Long_B",
		"Obstacle_Cross_B",
		"MazeWall_B",
		"MazeWall_D",
		"Hurdle_2",
		"Hurdle_3",
		"UpperBarrier_B",
	]:
		var node = get_node_or_null(node_name)
		if is_instance_valid(node):
			node.queue_free()
