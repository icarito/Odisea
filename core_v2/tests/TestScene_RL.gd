extends Spatial

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const FLOOR_Y = 1.0
const MAIN_MIN = Vector3(-21.0, FLOOR_Y, -21.0)
const MAIN_MAX = Vector3(21.0, FLOOR_Y, 21.0)
const STAGE_MAX_STEPS = 700

var _randomizer: RLSceneRandomizer = null

func _ready() -> void:
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_ensure_randomizer()
	if not _randomizer.has_pool("spawn_main"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()
	var pair = _randomizer.choose_episode(["spawn_main"], ["target_main"], 9.0, 34.0, 120)
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
	_randomizer.add_box_pool("spawn_main", MAIN_MIN, MAIN_MAX, 240, FLOOR_Y, 0.42)
	_randomizer.add_box_pool("target_main", MAIN_MIN, MAIN_MAX, 260, FLOOR_Y, 0.42)
