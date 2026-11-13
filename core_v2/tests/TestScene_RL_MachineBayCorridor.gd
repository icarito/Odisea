extends Spatial

# Gym RL estilo Bahía de Máquinas: corredor industrial largo (ancho 16, largo ~96)
# con bloques-estación a los lados (z ≈ 8/28/48/68), replicando el layout de la
# bahía (entrada z=-2, estaciones a lo largo de Z, salida z≈87) con primitivas,
# sin editar MachineBay.tscn.
#
# Pools: spawn en la zona de entrada (z -2..6), targets repartidos por el corredor
# (z 10..84), fuerzando recorridos largos pasando estaciones.

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const FLOOR_Y := 0.0
const HALF_W := 7.0
const STAGE_MAX_STEPS := 1100

var _randomizer: RLSceneRandomizer = null

func _ready() -> void:
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_ensure_randomizer()
	if not _randomizer.has_pool("spawn_main"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()
	var pair = _randomizer.choose_episode(["spawn_main"], ["target_main"], 14.0, 90.0, 160)
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
	_randomizer.add_box_pool(
		"spawn_main",
		Vector3(-4.0, FLOOR_Y, -2.0),
		Vector3(4.0, FLOOR_Y, 8.0),
		80, FLOOR_Y, 0.45
	)
	_randomizer.add_box_pool(
		"target_main",
		Vector3(-4.0, FLOOR_Y, 14.0),
		Vector3(4.0, FLOOR_Y, 84.0),
		200, FLOOR_Y, 0.45
	)
