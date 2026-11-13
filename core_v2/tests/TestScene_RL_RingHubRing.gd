extends Spatial

# Gym RL estilo RingHub: piso del domo (y=0) + anillo central elevado (deck y=4.5,
# outer 13 / inner 6, mismas medidas que el RingFloor del nivel) que actúa como
# obstáculo anular con soportes. El agente navega por el piso rodeando el hub,
# replicando el estilo del mapa nuevo sin editar RingHub_Level.tscn.
#
# Pools: spawn/target en el piso bajo alrededor del anillo (radio 16..30).

const RLSceneRandomizer = preload("res://core_v2/tests/RLSceneRandomizer.gd")

const FLOOR_Y := 0.0
const RING_DECK_Y := 4.5
const RING_INNER := 6.0
const RING_OUTER := 13.0
const POOL_MIN_R := 16.0
const POOL_MAX_R := 30.0
const STAGE_MAX_STEPS := 900

var _randomizer: RLSceneRandomizer = null

func _ready() -> void:
	_ensure_randomizer()

func anna_rl_before_episode_reset(_interface: AnnaInterface) -> void:
	_ensure_randomizer()
	if not _randomizer.has_pool("spawn_main"):
		_build_pools()

func anna_rl_choose_episode(_interface: AnnaInterface) -> Dictionary:
	_ensure_randomizer()
	var pair = _randomizer.choose_episode(["spawn_main"], ["target_main"], 12.0, 55.0, 140)
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
	# Piso alrededor del anillo central (evita el volumen del hub: r > 15).
	_randomizer.add_box_pool(
		"spawn_main",
		Vector3(-POOL_MAX_R, FLOOR_Y, -POOL_MAX_R),
		Vector3(POOL_MAX_R, FLOOR_Y, POOL_MAX_R),
		220, FLOOR_Y, 0.45
	)
	_randomizer.add_box_pool(
		"target_main",
		Vector3(-POOL_MAX_R, FLOOR_Y, -POOL_MAX_R),
		Vector3(POOL_MAX_R, FLOOR_Y, POOL_MAX_R),
		240, FLOOR_Y, 0.45
	)
