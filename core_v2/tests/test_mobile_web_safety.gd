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

func test_holoterminal_reduces_viewport_size_for_mobile_web() -> void:
	var holo = HoloTerminalScript.new()
	holo.screen_resolution = Vector2(1024, 768)

	assert_vector2(holo._resolve_viewport_target_size("HTML5", true)).is_equal(Vector2(512, 384))
	assert_vector2(holo._resolve_viewport_target_size("HTML5", true, "", "0.4")).is_equal(Vector2(409, 307))
	assert_vector2(holo._resolve_viewport_target_size("HTML5", false)).is_equal(Vector2(1024, 768))
	assert_vector2(holo._resolve_viewport_target_size("HTML5", true, "off")).is_equal(Vector2(1024, 768))

	holo.free()
