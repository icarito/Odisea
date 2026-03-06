extends GdUnitTestSuite

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
