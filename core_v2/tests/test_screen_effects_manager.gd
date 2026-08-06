extends GdUnitTestSuite

var _previous_screen_effects_env := ""

func before_test() -> void:
	_previous_screen_effects_env = OS.get_environment("OYS_SCREEN_EFFECTS")
	OS.set_environment("OYS_SCREEN_EFFECTS", "1")
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	if manager:
		manager.reset(true)

func after_test() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	if manager:
		manager.reset(true)
	OS.set_environment("OYS_SCREEN_EFFECTS", _previous_screen_effects_env)

func test_screen_effects_manager_mounts_overlay_and_toggles_cinematic_bars() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	var overlay_ui = get_tree().root.get_node_or_null("OverlayUIManager")
	assert_object(manager).is_not_null()
	assert_object(overlay_ui).is_not_null()

	manager.reset(true)
	manager.show_script_cinematic_bars(true)
	yield(get_tree(), "idle_frame")

	var passive_slot = overlay_ui.get_slot("Passive")
	var overlay = passive_slot.get_node_or_null("ScreenEffectsOverlay")
	assert_object(overlay).is_not_null()
	assert_bool(overlay.get_parent() == passive_slot).is_true()
	assert_bool(is_equal_approx(float(overlay.get("cinematic_progress")), 1.0)).is_true()

	manager.hide_script_cinematic_bars(true)
	assert_bool(is_equal_approx(float(overlay.get("cinematic_progress")), 0.0)).is_true()
	manager.reset(true)

func test_screen_effects_manager_death_cover_roundtrip() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	var overlay_ui = get_tree().root.get_node_or_null("OverlayUIManager")
	assert_object(manager).is_not_null()
	assert_object(overlay_ui).is_not_null()

	manager.reset(true)
	var cover_state = manager.begin_death_cover({"duration": 0.0})
	if cover_state is GDScriptFunctionState:
		yield(cover_state, "completed")

	var overlay = overlay_ui.get_slot("Passive").get_node_or_null("ScreenEffectsOverlay")
	assert_object(overlay).is_not_null()
	assert_bool(is_equal_approx(float(overlay.get("death_progress")), 1.0)).is_true()

	var clear_state = manager.end_death_cover({"duration": 0.0})
	if clear_state is GDScriptFunctionState:
		yield(clear_state, "completed")
	assert_bool(is_equal_approx(float(overlay.get("death_progress")), 0.0)).is_true()
	manager.reset(true)

func test_death_cover_mutes_level_audio_until_it_clears() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	var audio = get_tree().root.get_node_or_null("AudioManager")
	assert_object(manager).is_not_null()
	assert_object(audio).is_not_null()

	manager.reset(true)
	assert_bool(audio.is_level_audio_muted()).is_false()

	var cover_state = manager.begin_death_cover({"duration": 0.0})
	if cover_state is GDScriptFunctionState:
		yield(cover_state, "completed")
	assert_bool(audio.is_level_audio_muted()).is_true()

	var clear_state = manager.end_death_cover({"duration": 0.0})
	if clear_state is GDScriptFunctionState:
		yield(clear_state, "completed")
	assert_bool(audio.is_level_audio_muted()).is_false()

func test_death_cover_freezes_the_world_until_it_clears() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	assert_object(manager).is_not_null()

	manager.reset(true)
	assert_bool(get_tree().paused).is_false()

	var cover_state = manager.begin_death_cover({"duration": 0.0})
	if cover_state is GDScriptFunctionState:
		yield(cover_state, "completed")
	assert_bool(get_tree().paused).is_true()

	var clear_state = manager.end_death_cover({"duration": 0.0})
	if clear_state is GDScriptFunctionState:
		yield(clear_state, "completed")
	assert_bool(get_tree().paused).is_false()

# La pausa del árbol es compartida: si el jugador ya estaba en el menú de pausa cuando
# murió, el cover no debe quedarse con la llave y despausar el juego al reaparecer.
func test_death_cover_does_not_steal_a_pause_it_did_not_set() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	assert_object(manager).is_not_null()

	manager.reset(true)
	get_tree().paused = true
	var cover_state = manager.begin_death_cover({"duration": 0.0})
	if cover_state is GDScriptFunctionState:
		yield(cover_state, "completed")

	var clear_state = manager.end_death_cover({"duration": 0.0})
	if clear_state is GDScriptFunctionState:
		yield(clear_state, "completed")
	assert_bool(get_tree().paused).is_true()

	get_tree().paused = false

func test_screen_effects_manager_skips_death_confirm_in_cli_mode() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	var session = get_tree().root.get_node_or_null("SessionManager")
	assert_object(manager).is_not_null()
	assert_object(session).is_not_null()

	var previous_cli_mode = bool(session.is_cli_mode)
	session.is_cli_mode = true
	var wait_state = manager.wait_for_death_confirm()
	assert_bool(wait_state == null).is_true()
	session.is_cli_mode = previous_cli_mode
