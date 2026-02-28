extends Spatial

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const GROUND_Y = 1.0
const UPPER_Y = 5.0
const STAGE_MAX_STEPS = 1100

var _randomizer: RLSceneRandomizer = null

func _ready() -> void:
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_ensure_randomizer()
	if not _randomizer.has_pool("spawn_ground"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()

	var spawn_pools = ["spawn_ground", "spawn_ground", "spawn_upper"]
	var target_pools = ["target_ground", "target_upper", "target_upper"]
	var pair = _randomizer.choose_episode(spawn_pools, target_pools, 10.0, 40.0, 180)
	if pair.empty():
		return {}
	pair["max_steps"] = STAGE_MAX_STEPS
	return pair

func _ensure_randomizer() -> void:
	if _randomizer != null:
		return
	_randomizer = RLSceneRandomizer.new()
	_randomizer.configure(self)
	_build_pools()

func _build_pools() -> void:
	_randomizer.clear()
	_randomizer.add_box_pool("spawn_ground", Vector3(-20.0, GROUND_Y, -20.0), Vector3(20.0, GROUND_Y, 20.0), 220, GROUND_Y, 0.45)
	_randomizer.add_box_pool("spawn_upper", Vector3(-8.0, UPPER_Y, -8.0), Vector3(8.0, UPPER_Y, 8.0), 140, UPPER_Y, 0.45)
	_randomizer.add_box_pool("target_ground", Vector3(-20.0, GROUND_Y, -20.0), Vector3(20.0, GROUND_Y, 20.0), 200, GROUND_Y, 0.45)
	_randomizer.add_box_pool("target_upper", Vector3(-8.5, UPPER_Y, -8.5), Vector3(8.5, UPPER_Y, 8.5), 180, UPPER_Y, 0.45)
