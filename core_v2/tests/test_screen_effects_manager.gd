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

func test_screen_effects_manager_exposes_safe_margins_for_cinematic_bars() -> void:
	var manager = get_tree().root.get_node_or_null("ScreenEffectsManager")
	var overlay_ui = get_tree().root.get_node_or_null("OverlayUIManager")
	assert_object(manager).is_not_null()
	assert_object(overlay_ui).is_not_null()

	manager.reset(true)
	manager.show_script_cinematic_bars(true)
	yield(get_tree(), "idle_frame")

	var margins = overlay_ui.get_safe_margins()
	assert_float(float(margins.get("top", 0.0))).is_greater(0.0)
	assert_float(float(margins.get("bottom", 0.0))).is_greater(0.0)

	manager.hide_script_cinematic_bars(true)
	yield(get_tree(), "idle_frame")

	var cleared_margins = overlay_ui.get_safe_margins()
	assert_float(float(cleared_margins.get("top", 0.0))).is_equal(0.0)
	assert_float(float(cleared_margins.get("bottom", 0.0))).is_equal(0.0)

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
