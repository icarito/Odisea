extends Spatial

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const FLOOR_Y = 1.0
const STAGE_MAX_STEPS = 900

var _randomizer: RLSceneRandomizer = null
var _stage_max_steps := STAGE_MAX_STEPS

func _ready() -> void:
	_stage_max_steps = _resolve_stage_max_steps()
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_ensure_randomizer()
	if not _randomizer.has_pool("spawn_north"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()
	var pair = _randomizer.choose_episode(
		["spawn_north", "spawn_south", "spawn_west", "spawn_east"],
		["target_north", "target_south", "target_west", "target_east"],
		11.0,
		36.0,
		160
	)
	if pair.empty():
		return {}
	pair["max_steps"] = _stage_max_steps
	return pair

func _resolve_stage_max_steps() -> int:
	var max_steps_env = OS.get_environment("ANNA_RL_MAX_STEPS")
	if max_steps_env.is_valid_integer():
		return int(max(100, int(max_steps_env)))
	return STAGE_MAX_STEPS

func _ensure_randomizer() -> void:
	if _randomizer != null:
		return
	_randomizer = RLSceneRandomizer.new()
	_randomizer.configure(self)
	_build_pools()

func _build_pools() -> void:
	_randomizer.clear()
	# Spawn/target corridors around obstacles.
	_randomizer.add_box_pool("spawn_north", Vector3(-18.0, FLOOR_Y, -20.0), Vector3(18.0, FLOOR_Y, -8.0), 140, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("spawn_south", Vector3(-18.0, FLOOR_Y, 8.0), Vector3(18.0, FLOOR_Y, 20.0), 140, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("spawn_west", Vector3(-20.0, FLOOR_Y, -8.0), Vector3(-8.0, FLOOR_Y, 8.0), 120, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("spawn_east", Vector3(8.0, FLOOR_Y, -8.0), Vector3(20.0, FLOOR_Y, 8.0), 120, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("target_north", Vector3(-18.0, FLOOR_Y, -20.0), Vector3(18.0, FLOOR_Y, -8.0), 150, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("target_south", Vector3(-18.0, FLOOR_Y, 8.0), Vector3(18.0, FLOOR_Y, 20.0), 150, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("target_west", Vector3(-20.0, FLOOR_Y, -8.0), Vector3(-8.0, FLOOR_Y, 8.0), 130, FLOOR_Y, 0.45)
	_randomizer.add_box_pool("target_east", Vector3(8.0, FLOOR_Y, -8.0), Vector3(20.0, FLOOR_Y, 8.0), 130, FLOOR_Y, 0.45)
