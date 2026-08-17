extends GdUnitTestSuite

const MobileUIManagerScript = preload("res://core_v2/autoloads/MobileUIManager.gd")
const InputProviderV2Script = preload("res://core_v2/input/InputProviderV2.gd")
const PlayerControllerV2Script = preload("res://core_v2/player/PlayerControllerV2.gd")

func test_mobile_ui_manager_runtime_touch_detection() -> void:
	var mgr = MobileUIManagerScript.new()
	get_tree().root.add_child(mgr)
	mgr.touch_idle_timeout = 5.0
	mgr._is_mobile = false
	mgr._is_touch_active = false

	assert_bool(mgr.is_touch_active()).is_false()

	var touch_event = InputEventScreenTouch.new()
	touch_event.pressed = true
	touch_event.index = 0
	touch_event.position = Vector2(100, 100)

	mgr._input(touch_event)

	assert_bool(mgr.is_mobile()).is_true()
	assert_bool(mgr.is_touch_active()).is_true()
	assert_object(mgr._mobile_ui).is_not_null()
	assert_bool(mgr._mobile_ui.visible).is_true()

	mgr.queue_free()


func test_mobile_ui_manager_idle_timeout() -> void:
	var mgr = MobileUIManagerScript.new()
	get_tree().root.add_child(mgr)
	mgr.touch_idle_timeout = 2.0
	mgr._is_mobile = true
	mgr._is_touch_active = true
	mgr._spawn_mobile_ui()
	mgr._refresh_mobile_ui_visibility()

	assert_bool(mgr._mobile_ui.visible).is_true()

	# Advance process time past timeout
	mgr._process(1.0)
	assert_bool(mgr.is_touch_active()).is_true()

	mgr._process(1.5)
	assert_bool(mgr.is_touch_active()).is_false()
	assert_bool(mgr._mobile_ui.visible).is_false()

	# Touch screen again to wake up
	var touch_event = InputEventScreenTouch.new()
	touch_event.pressed = true
	touch_event.index = 0
	touch_event.position = Vector2(150, 150)
	mgr._input(touch_event)

	assert_bool(mgr.is_touch_active()).is_true()
	assert_bool(mgr._mobile_ui.visible).is_true()

	mgr.queue_free()


func test_input_provider_touch_hint_sync() -> void:
	var provider = InputProviderV2Script.new()
	provider.set_touch_ui_hint(false)
	assert_bool(provider._has_touch_ui()).is_false()

	provider.set_touch_ui_hint(true)
	assert_bool(provider._has_touch_ui()).is_true()


func test_player_controller_touch_tap_and_mouse_filter() -> void:
	var player = PlayerControllerV2Script.new()
	get_tree().root.add_child(player)

	# Add dummy control in group touch_control
	var touch_btn = Button.new()
	touch_btn.add_to_group("touch_control")
	touch_btn.rect_global_position = Vector2(10, 10)
	touch_btn.rect_size = Vector2(100, 100)
	touch_btn.visible = true
	get_tree().root.add_child(touch_btn)

	# Touch over touch control -> should be ignored for tap interact
	assert_bool(player._is_over_touch_control(Vector2(50, 50))).is_true()
	assert_bool(player._is_over_touch_control(Vector2(300, 300))).is_false()

	# Simulate short tap outside touch control
	var touch_press = InputEventScreenTouch.new()
	touch_press.pressed = true
	touch_press.index = 1
	touch_press.position = Vector2(300, 300)
	player._input(touch_press)

	assert_int(player._touch_tap_index).is_equal(1)

	var touch_release = InputEventScreenTouch.new()
	touch_release.pressed = false
	touch_release.index = 1
	touch_release.position = Vector2(302, 302)
	player._input(touch_release)

	assert_int(player._touch_tap_index).is_equal(-1)
	assert_bool(OS.get_ticks_msec() < player._ignore_emulated_mouse_until).is_true()

	touch_btn.queue_free()
	player.queue_free()
