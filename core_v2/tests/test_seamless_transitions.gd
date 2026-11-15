extends GdUnitTestSuite

# FD-021/FD-297 polish: mecanismo común seamless (modo "seamless" de SceneManager +
# lift del AirlockManager). El espacio físico de transición actúa como buffer: el swap
# ocurre detrás de las puertas cerradas, sin fade ni cartel, y el audio cruza sin corte.
#
# Estos tests cubren la DECISIÓN y el PAYLOAD del mecanismo, no el swap vivo (eso lo
# cubren los OYS/otros tests de airlock con fan real). Evitan llamar notify_transition()
# del AirlockManager real: arma estado de autoload que contamina suites siguientes en el
# mismo proceso (ver el warning en test_dome_crio_airlock_transition.gd).

const TransitionPortalScript = preload("res://core_v2/components/TransitionPortal.gd")
const TubeAirlockScript = preload("res://core_v2/props/tube/TubeAirlock.gd")

# --- SceneManager: modo seamless ---

func test_scene_manager_seamless_mode_disables_fade_and_loading() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	assert_object(manager).is_not_null()
	if manager == null:
		return
	manager._transition_params = {"transition": "seamless"}
	assert_str(manager._get_transition_mode()).is_equal("seamless")
	assert_bool(manager._should_use_fade("seamless")).is_false()
	assert_bool(manager._should_show_loading("seamless")).is_false()
	# Incluso con show_loading explícito, el modo seamless no muestra cartel.
	manager._transition_params = {"transition": "seamless", "show_loading": true}
	assert_bool(manager._should_show_loading("seamless")).is_false()
	manager._transition_params = {}

func test_scene_manager_legacy_modes_unchanged() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	assert_object(manager).is_not_null()
	if manager == null:
		return
	assert_bool(manager._should_use_fade("fade")).is_true()
	assert_bool(manager._should_use_fade("none")).is_false()
	manager._transition_params = {"show_loading": true}
	assert_bool(manager._should_show_loading("fade")).is_true()
	manager._transition_params = {}

func _snapshot_airlock_manager() -> Dictionary:
	var am := get_node_or_null("/root/AirlockManager")
	if am == null:
		return {}
	return {"node": am, "pending": am._pending_transition, "seamless": am._seamless_swap}

func _restore_airlock_manager(saved: Dictionary) -> void:
	if saved.empty():
		return
	var am = saved["node"]
	am._pending_transition = saved["pending"]
	am._seamless_swap = saved["seamless"]

func test_scene_manager_auto_upgrades_to_seamless_when_armed() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	assert_object(manager).is_not_null()
	if manager == null:
		return
	var saved := _snapshot_airlock_manager()
	if saved.empty():
		return
	var am = saved["node"]
	am._seamless_swap = true
	am._pending_transition = true
	manager._transition_params = {}
	manager._maybe_upgrade_seamless()
	assert_str(manager._transition_params.get("transition", "")).is_equal("seamless")
	manager._transition_params = {}
	_restore_airlock_manager(saved)

func test_scene_manager_no_upgrade_when_not_armed() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	assert_object(manager).is_not_null()
	if manager == null:
		return
	var saved := _snapshot_airlock_manager()
	if not saved.empty():
		var am = saved["node"]
		am._seamless_swap = false
		am._pending_transition = false
	manager._transition_params = {}
	manager._maybe_upgrade_seamless()
	assert_bool(manager._transition_params.has("transition")).is_false()
	manager._transition_params = {}
	if not saved.empty():
		_restore_airlock_manager(saved)

func test_scene_manager_explicit_transition_beats_auto_upgrade() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	assert_object(manager).is_not_null()
	if manager == null:
		return
	var saved := _snapshot_airlock_manager()
	if not saved.empty():
		var am = saved["node"]
		am._seamless_swap = true
		am._pending_transition = true
	manager._transition_params = {"transition": "fade"}
	manager._maybe_upgrade_seamless()
	assert_str(manager._transition_params.get("transition", "")).is_equal("fade")
	manager._transition_params = {}
	if not saved.empty():
		_restore_airlock_manager(saved)

# --- TransitionPortal: params seamless ---

func test_transition_portal_seamless_params_preserves_fields() -> void:
	var portal = auto_free(TransitionPortalScript.new())
	add_child(portal)
	var base := {
		"spawn_id": "from_int",
		"target_spawn_id": "from_int",
		"transition": "fade",
		"preserve_player_state": true,
		"fade_out": 0.2,
		"fade_in": 0.2,
		"show_loading": false,
		"state_data": {}
	}
	var seamless: Dictionary = portal._seamless_params(base)
	assert_str(seamless["transition"]).is_equal("seamless")
	assert_float(seamless["fade_out"]).is_equal(0.0)
	assert_float(seamless["fade_in"]).is_equal(0.0)
	assert_bool(seamless.has("show_loading")).is_false()
	assert_str(seamless["target_spawn_id"]).is_equal("from_int")
	assert_bool(seamless["preserve_player_state"]).is_true()
	# El dict original queda intacto (copia).
	assert_str(base["transition"]).is_equal("fade")
	assert_float(base["fade_out"]).is_equal(0.2)

# --- TubeAirlock: params seamless ---

func test_tube_airlock_builds_seamless_params() -> void:
	var tube = auto_free(TubeAirlockScript.new())
	add_child(tube)
	tube.target_spawn = "end"
	var params: Dictionary = tube._build_seamless_params()
	assert_str(params["transition"]).is_equal("seamless")
	assert_str(params["target_spawn_id"]).is_equal("end")
	assert_bool(params["preserve_player_state"]).is_false()
	assert_float(params["fade_out"]).is_equal(0.0)
	assert_float(params["fade_in"]).is_equal(0.0)
	assert_bool(params["wait_for_fade_out"]).is_false()
