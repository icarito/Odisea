extends Spatial

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const FLOOR_Y = 1.0
const STAGE_MAX_STEPS = 1400
const DOOR_REQUIRED_PROB = 1.0
const FORCE_FIXED_ROUTE = true
const FIXED_SPAWN = Vector3(5.0, 2.5, 16.0)
const FIXED_TARGET = Vector3(5.0, FLOOR_Y, -8.0)

var _randomizer: RLSceneRandomizer = null

func _ready() -> void:
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_reset_gate_state()
	_ensure_randomizer()
	if not _randomizer.has_pool("spawn_start"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()
	if _use_fixed_route():
		return {
			"spawn": FIXED_SPAWN,
			"target": FIXED_TARGET,
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
		pair["target"] = Vector3(5.0, FLOOR_Y, -8.0)
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
	return FORCE_FIXED_ROUTE

func _get_door_required_prob() -> float:
	var env = OS.get_environment("ANNA_RL_DOOR_REQUIRED_PROB")
	if env.is_valid_float():
		return clamp(float(env), 0.0, 1.0)
	return DOOR_REQUIRED_PROB

func _get_stage_max_steps() -> int:
	var env = OS.get_environment("ANNA_RL_MAX_STEPS")
	if env.is_valid_integer():
		return int(max(100, int(env)))
	return STAGE_MAX_STEPS

func _ensure_randomizer() -> void:
	if _randomizer != null:
		return
	_randomizer = RLSceneRandomizer.new()
	_randomizer.configure(self)
	_build_pools()

func _build_pools() -> void:
	_randomizer.clear()
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
