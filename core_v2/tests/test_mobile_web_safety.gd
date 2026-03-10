extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const SessionManagerScript = preload("res://core_v2/autoloads/SessionManager.gd")
const HoloTerminalScript = preload("res://core_v2/things/HoloTerminalV2.gd")

func test_session_manager_detects_mobile_web_safety_mode() -> void:
	var sm = SessionManagerScript.new()

	assert_bool(sm._should_enable_mobile_web_safety("HTML5", true)).is_true()
	assert_bool(sm._should_enable_mobile_web_safety("HTML5", false)).is_false()
	assert_bool(sm._should_enable_mobile_web_safety("Windows", true)).is_false()
	assert_bool(sm._should_enable_mobile_web_safety("Windows", false, "on")).is_true()
	assert_bool(sm._should_enable_mobile_web_safety("HTML5", true, "off")).is_false()

	sm.free()

func test_session_manager_computes_downscaled_mobile_web_render_size() -> void:
	var sm = SessionManagerScript.new()

	assert_vector2(sm._compute_mobile_web_render_size(Vector2(1170, 2532), 0.67)).is_equal(Vector2(783, 1696))
	assert_vector2(sm._compute_mobile_web_render_size(Vector2(390, 844), 0.67)).is_equal(Vector2(320, 565))

	sm.free()

func test_mobile_web_safety_defaults_to_medium_profile() -> void:
	var sm = SessionManagerScript.new()
	var prev_profile = OS.get_environment("ODISEA_GRAPHICS_PROFILE")
	var prev_target_fps = OS.get_environment("ODISEA_TARGET_FPS")
	var prev_weak = OS.get_environment("ODISEA_WEB_WEAK_DEVICE")

	OS.set_environment("ODISEA_GRAPHICS_PROFILE", "")
	OS.set_environment("ODISEA_TARGET_FPS", "")
	OS.set_environment("ODISEA_WEB_WEAK_DEVICE", "")

	sm._apply_mobile_web_safety_hints()

	assert_str(OS.get_environment("ODISEA_GRAPHICS_PROFILE")).is_equal("medium")
	assert_str(OS.get_environment("ODISEA_TARGET_FPS")).is_equal("30")
	assert_str(OS.get_environment("ODISEA_WEB_WEAK_DEVICE")).is_equal("1")

	OS.set_environment("ODISEA_GRAPHICS_PROFILE", prev_profile)
	OS.set_environment("ODISEA_TARGET_FPS", prev_target_fps)
	OS.set_environment("ODISEA_WEB_WEAK_DEVICE", prev_weak)
	sm.free()

func test_holoterminal_reduces_viewport_size_for_mobile_web() -> void:
	var holo = HoloTerminalScript.new()
	holo.screen_resolution = Vector2(1024, 768)

	assert_vector2(holo._resolve_viewport_target_size("HTML5", true)).is_equal(Vector2(512, 384))
	assert_vector2(holo._resolve_viewport_target_size("HTML5", true, "", "0.4")).is_equal(Vector2(409, 307))
	assert_vector2(holo._resolve_viewport_target_size("HTML5", false)).is_equal(Vector2(1024, 768))
	assert_vector2(holo._resolve_viewport_target_size("HTML5", true, "off")).is_equal(Vector2(1024, 768))

	holo.free()
