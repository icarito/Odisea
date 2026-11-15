extends GdUnitTestSuite

# Test focalizado de HangarTransition (FD-289 §7.5/§7.9, tracker #319).
#
# Es la frontera interior -> interior del descenso domo -> hangar: un Area que hace
# SceneManager.goto_scene a la escena del hangar con el spawn `from_dome_intro_platform`.
# Mismo patron que RingHub <-> Bahia (BayAirlockTrigger): guard de doble disparo, gracia
# post-carga y destino resuelto por export o por la config del domo.
#
# No corre la suite completa (AGENTS.md §6.1).

const TransitionScript = preload("res://core_v2/props/hangar/HangarTransition.gd")

const HANGAR_SCENE := "res://core_v2/levels/interiors/Dome_Intro_Hangar.tscn"
const HANGAR_SPAWN := "from_dome_intro_platform"


class FakeSceneManager:
	extends Node
	var calls := []
	func goto_scene(path, params := {}):
		calls.append({"path": path, "params": params.duplicate(true)})
		return true


class FakeDirector:
	extends Node
	var scene := ""
	var spawn := ""
	func get_hangar_scene() -> String:
		return scene
	func get_hangar_spawn_id() -> String:
		return spawn


class FakePlayer:
	extends KinematicBody
	func _init() -> void:
		add_to_group("player")


class FakeBody:
	extends KinematicBody


func _make_transition(manager = null) -> Area:
	var t = auto_free(TransitionScript.new())
	if manager != null:
		t.scene_manager_override = manager
	add_child(t)
	return t


func _capture_request(target_scene, target_spawn, sink: Array) -> void:
	sink.append({"scene": target_scene, "spawn": target_spawn})


# --- Resolucion de destino ---

func test_explicit_exports_win_over_config() -> void:
	var t = _make_transition()
	t.target_scene = HANGAR_SCENE
	t.target_spawn_id = HANGAR_SPAWN
	assert_str(t.resolve_target_scene()).is_equal(HANGAR_SCENE)
	assert_str(t.resolve_target_spawn_id()).is_equal(HANGAR_SPAWN)


func test_empty_exports_fall_back_to_dome_config() -> void:
	var director = auto_free(FakeDirector.new())
	add_child(director)
	director.scene = "res://core_v2/levels/interiors/Some_Hangar.tscn"
	director.spawn = "spawn_from_director"

	var t = _make_transition()
	t.target_scene = ""
	t.target_spawn_id = ""
	t.use_dome_config = true
	t.director_path = director.get_path()

	assert_str(t.resolve_target_scene()).is_equal("res://core_v2/levels/interiors/Some_Hangar.tscn")
	assert_str(t.resolve_target_spawn_id()).is_equal("spawn_from_director")


func test_missing_target_does_not_emit_or_transition() -> void:
	var sm = auto_free(FakeSceneManager.new())
	add_child(sm)
	var t = _make_transition(sm)
	t.target_scene = ""
	t.use_dome_config = false

	var requests: Array = []
	t.connect("transition_requested", self, "_capture_request", [requests])

	assert_bool(t._transition_to_target()).is_false()
	assert_array(requests).is_empty()
	assert_array(sm.calls).is_empty()


# --- Disparo por entrada del jugador ---

func test_player_entry_triggers_once_and_calls_goto_scene() -> void:
	var sm = auto_free(FakeSceneManager.new())
	add_child(sm)
	var t = _make_transition(sm)
	t.target_scene = HANGAR_SCENE
	t.target_spawn_id = HANGAR_SPAWN

	var requests: Array = []
	t.connect("transition_requested", self, "_capture_request", [requests])

	var player = auto_free(FakePlayer.new())
	add_child(player)

	t._on_body_entered(player)

	assert_bool(t.is_triggered()).is_true()
	assert_array(requests).contains_exactly([{"scene": HANGAR_SCENE, "spawn": HANGAR_SPAWN}])
	assert_int(sm.calls.size()).is_equal(1)
	assert_str(sm.calls[0]["path"]).is_equal(HANGAR_SCENE)
	assert_str(sm.calls[0]["params"]["target_spawn_id"]).is_equal(HANGAR_SPAWN)
	assert_bool(sm.calls[0]["params"]["preserve_player_state"]).is_false()
	assert_bool(sm.calls[0]["params"].get("wait_for_fade_out", false)).is_true()

	# Segundo cuerpo (o el mismo otra vez): no re-dispara.
	t._on_body_entered(player)
	assert_int(sm.calls.size()).is_equal(1)


func test_non_player_body_is_ignored() -> void:
	var sm = auto_free(FakeSceneManager.new())
	add_child(sm)
	var t = _make_transition(sm)
	t.target_scene = HANGAR_SCENE
	t.target_spawn_id = HANGAR_SPAWN

	var box = auto_free(FakeBody.new())
	add_child(box)
	t._on_body_entered(box)

	assert_bool(t.is_triggered()).is_false()
	assert_array(sm.calls).is_empty()


func test_post_transition_grace_frames_block_immediate_retrigger() -> void:
	var sm = auto_free(FakeSceneManager.new())
	add_child(sm)
	var t = _make_transition(sm)
	t.target_scene = HANGAR_SCENE
	t.target_spawn_id = HANGAR_SPAWN

	var player = auto_free(FakePlayer.new())
	add_child(player)

	# Recien cargada ESTA escena: el jugador aparece dentro del volumen de destino y no debe
	# rebotar a una transicion de vuelta.
	t._scene_ready_frame = Engine.get_physics_frames()
	t._on_body_entered(player)
	assert_bool(t.is_triggered()).is_false()
	assert_array(sm.calls).is_empty()

	# Pasada la gracia, sí dispara.
	t._scene_ready_frame = Engine.get_physics_frames() - 1000
	t._on_body_entered(player)
	assert_bool(t.is_triggered()).is_true()
	assert_int(sm.calls.size()).is_equal(1)
