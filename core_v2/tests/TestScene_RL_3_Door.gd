extends Spatial

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const FLOOR_Y = 1.0
const STAGE_MAX_STEPS = 1400
const DOOR_REQUIRED_PROB = 1.0
const FORCE_FIXED_ROUTE = true
const FIXED_SPAWN = Vector3(5.0, 2.5, 16.0)
const FIXED_TARGET = Vector3(5.0, FLOOR_Y, -8.0)
const DIDACTIC_FIXED_TARGET = Vector3(5.0, FLOOR_Y, -6.0)

var _randomizer: RLSceneRandomizer = null
var _didactic_mode := false

func _ready() -> void:
	_didactic_mode = _is_didactic_enabled()
	if _didactic_mode:
		_apply_didactic_geometry()
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_reset_gate_state()
	_ensure_randomizer()
	if not _randomizer.has_pool("spawn_start"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()
	if _use_fixed_route():
		var fixed_target = DIDACTIC_FIXED_TARGET if _didactic_mode else FIXED_TARGET
		return {
			"spawn": FIXED_SPAWN,
			"target": fixed_target,
			"door_required": true,
			"max_steps": _get_stage_max_steps()
		}
	var use_door_route = randf() < _get_door_required_prob()
	var pair := {}
	if use_door_route:
		pair = _randomizer.choose_episode(["spawn_start"], ["target_far"], 9.0, 48.0, 180)
	else:
		pair = _randomizer.choose_episode(["spawn_free"], ["target_free"], 7.0, 52.0, 180)
	if pair.empty():
		pair["spawn"] = FIXED_SPAWN
		pair["target"] = DIDACTIC_FIXED_TARGET if _didactic_mode else FIXED_TARGET
		pair["door_required"] = true
		pair["max_steps"] = _get_stage_max_steps()
		return pair
	pair["max_steps"] = _get_stage_max_steps()
	pair["door_required"] = use_door_route
	return pair

func _use_fixed_route() -> bool:
	var env = OS.get_environment("ANNA_RL_DOOR_FIXED_ROUTE")
	if env != "":
		return env.to_lower() in ["1", "true", "yes", "on"]
	if _didactic_mode:
		return true
	return FORCE_FIXED_ROUTE

func _get_door_required_prob() -> float:
	var env = OS.get_environment("ANNA_RL_DOOR_REQUIRED_PROB")
	if env.is_valid_float():
		return clamp(float(env), 0.0, 1.0)
	if _didactic_mode:
		return 1.0
	return DOOR_REQUIRED_PROB

func _get_stage_max_steps() -> int:
	var env = OS.get_environment("ANNA_RL_MAX_STEPS")
	if env.is_valid_integer():
		return int(max(100, int(env)))
	if _didactic_mode:
		return int(max(STAGE_MAX_STEPS, 1600))
	return STAGE_MAX_STEPS

func _ensure_randomizer() -> void:
	if _randomizer != null:
		return
	_randomizer = RLSceneRandomizer.new()
	_randomizer.configure(self)
	_build_pools()

func _build_pools() -> void:
	_randomizer.clear()
	if _didactic_mode:
		# Structured route: start chamber -> gate -> short post-door corridor.
		_randomizer.add_box_pool("spawn_start", Vector3(3.2, FLOOR_Y, 13.0), Vector3(6.8, FLOOR_Y, 18.5), 120, FLOOR_Y, 0.30)
		_randomizer.add_box_pool("target_far", Vector3(3.0, FLOOR_Y, -8.5), Vector3(7.2, FLOOR_Y, -2.8), 170, FLOOR_Y, 0.30)
		_randomizer.add_box_pool("spawn_free", Vector3(1.0, FLOOR_Y, 10.5), Vector3(9.0, FLOOR_Y, 19.5), 150, FLOOR_Y, 0.30)
		_randomizer.add_box_pool("target_free", Vector3(0.0, FLOOR_Y, -10.5), Vector3(12.0, FLOOR_Y, -1.5), 190, FLOOR_Y, 0.32)
		return
	# Start chamber and post-door area.
	_randomizer.add_box_pool("spawn_start", Vector3(2.0, FLOOR_Y, 12.0), Vector3(8.0, FLOOR_Y, 19.0), 160, FLOOR_Y, 0.35)
	_randomizer.add_box_pool("target_far", Vector3(-10.0, FLOOR_Y, -14.0), Vector3(22.0, FLOOR_Y, 2.0), 220, FLOOR_Y, 0.45)
	# Free mode pools.
	_randomizer.add_box_pool("spawn_free", Vector3(-22.0, FLOOR_Y, -22.0), Vector3(22.0, FLOOR_Y, 22.0), 240, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("target_free", Vector3(-22.0, FLOOR_Y, -22.0), Vector3(22.0, FLOOR_Y, 22.0), 260, FLOOR_Y, 0.45)

func _reset_gate_state() -> void:
	var gate = get_node_or_null("GateDoor")
	if not is_instance_valid(gate):
		return
	if "is_used" in gate:
		gate.is_used = false
	if "target_progress" in gate:
		gate.target_progress = 0.0
	if "anim_progress" in gate:
		gate.anim_progress = 0.0
	if gate.has_method("set_active"):
		gate.set_active(false, true)

func _is_didactic_enabled() -> bool:
	var scene_flag = OS.get_environment("ANNA_RL_DIDACTIC_RL3")
	if scene_flag != "":
		return scene_flag.to_lower() in ["1", "true", "yes", "on"]
	var global_flag = OS.get_environment("ANNA_RL_DIDACTIC")
	if global_flag != "":
		return global_flag.to_lower() in ["1", "true", "yes", "on"]
	return false

func _apply_didactic_geometry() -> void:
	for node_name in [
		"DoorVaultBlocker_Start",
		"DoorVaultBlocker_Maze",
		"MazeWall_B",
		"MazeWall_D",
		"Pillar_2",
	]:
		var node = get_node_or_null(node_name)
		if is_instance_valid(node):
			node.queue_free()
	var gate = get_node_or_null("GateDoor")
	if is_instance_valid(gate):
		if "size" in gate:
			gate.size = Vector3(4.2, 3.2, 0.4)
		if "slide_vector" in gate:
			gate.slide_vector = Vector3(0, 3.8, 0)
