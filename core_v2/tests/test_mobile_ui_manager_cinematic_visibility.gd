extends GdUnitTestSuite

const MobileUIManagerScript = preload("res://core_v2/autoloads/MobileUIManager.gd")

class DummyInputProvider:
	extends Reference
	var hardware_input_enabled := true


class DummyPlayer:
	extends KinematicBody
	var input_provider = null


func test_touch_ui_shows_skip_while_cinematic_is_active() -> void:
	var cinematic_manager = get_tree().root.get_node_or_null("CinematicManager")
	assert_object(cinematic_manager).is_not_null()

	var mobile_ui_manager = MobileUIManagerScript.new()
	get_tree().root.add_child(mobile_ui_manager)
	mobile_ui_manager._is_mobile = true
	mobile_ui_manager._spawn_mobile_ui()
	mobile_ui_manager._connect_cinematic_manager()
	mobile_ui_manager._refresh_mobile_ui_visibility()

	assert_object(mobile_ui_manager._mobile_ui).is_not_null()
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()

	var request_id = cinematic_manager.request_camera_mode(
		cinematic_manager.ControlMode.LOCKED_VIEW,
		{},
		"legacy_direct",
		10
	)
	cinematic_manager.emit_signal("cinematic_started", "intro")
	# During a legacy cinematic the MobileUI stays visible to show the skip button
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()
	var skip_btn = mobile_ui_manager._mobile_ui.get_node_or_null("Container/SkipButton")
	assert_object(skip_btn).is_not_null()
	assert_bool(skip_btn.visible).is_true()

	cinematic_manager.release_camera_request(request_id)
	cinematic_manager.emit_signal("cinematic_stopped")
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()
	if is_instance_valid(skip_btn):
		assert_bool(skip_btn.visible).is_false()

	mobile_ui_manager.queue_free()


func test_touch_ui_stays_visible_for_camera_zone_cinematics() -> void:
	var cinematic_manager = get_tree().root.get_node_or_null("CinematicManager")
	assert_object(cinematic_manager).is_not_null()

	var mobile_ui_manager = MobileUIManagerScript.new()
	get_tree().root.add_child(mobile_ui_manager)
	mobile_ui_manager._is_mobile = true
	mobile_ui_manager._spawn_mobile_ui()
	mobile_ui_manager._connect_cinematic_manager()
	mobile_ui_manager._refresh_mobile_ui_visibility()

	assert_object(mobile_ui_manager._mobile_ui).is_not_null()
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()

	var request_id = cinematic_manager.request_camera_mode(
		cinematic_manager.ControlMode.LOCKED_VIEW,
		{},
		"zone_ElevatorCameraZone",
		5
	)
	cinematic_manager.emit_signal("cinematic_started", "ElevatorZone")
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()

	cinematic_manager.release_camera_request(request_id)
	cinematic_manager.emit_signal("cinematic_stopped")

	mobile_ui_manager.queue_free()


func test_touch_ui_is_hidden_when_script_input_is_blocked() -> void:
	var session_manager = get_tree().root.get_node_or_null("SessionManager")
	assert_object(session_manager).is_not_null()

	var prev_player = session_manager.player
	var fake_player = DummyPlayer.new()
	var fake_input_provider = DummyInputProvider.new()
	fake_player.input_provider = fake_input_provider
	session_manager.player = fake_player

	var mobile_ui_manager = MobileUIManagerScript.new()
	get_tree().root.add_child(mobile_ui_manager)
	mobile_ui_manager._is_mobile = true
	mobile_ui_manager._spawn_mobile_ui()
	mobile_ui_manager._refresh_mobile_ui_visibility()

	assert_object(mobile_ui_manager._mobile_ui).is_not_null()
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()

	fake_input_provider.hardware_input_enabled = false
	mobile_ui_manager._refresh_mobile_ui_visibility()
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_false()

	fake_input_provider.hardware_input_enabled = true
	mobile_ui_manager._refresh_mobile_ui_visibility()
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()

	mobile_ui_manager.queue_free()
	session_manager.player = prev_player
	fake_player.free()


func test_hidden_touch_ui_does_not_reserve_subtitle_margins() -> void:
	var mobile_ui_manager = MobileUIManagerScript.new()
	get_tree().root.add_child(mobile_ui_manager)
	mobile_ui_manager._is_mobile = true
	mobile_ui_manager._spawn_mobile_ui()

	assert_object(mobile_ui_manager._mobile_ui).is_not_null()
	assert_bool(mobile_ui_manager._mobile_ui.visible).is_true()
	var visible_margins = mobile_ui_manager.get_reserved_overlay_margins()
	assert_float(float(visible_margins.get("bottom", 0.0))).is_greater(0.0)

	mobile_ui_manager._mobile_ui.visible = false
	var hidden_margins = mobile_ui_manager.get_reserved_overlay_margins()
	assert_float(float(hidden_margins.get("left", 0.0))).is_equal(0.0)
	assert_float(float(hidden_margins.get("right", 0.0))).is_equal(0.0)
	assert_float(float(hidden_margins.get("bottom", 0.0))).is_equal(0.0)

	mobile_ui_manager.queue_free()
