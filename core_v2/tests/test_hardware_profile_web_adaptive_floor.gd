extends GdUnitTestSuite

const HardwareProfileScript = preload("res://core_v2/autoloads/HardwareProfile.gd")


func test_html5_adaptive_degrade_stops_at_medium() -> void:
	var hp = get_tree().root.get_node_or_null("HardwareProfile")
	assert_object(hp).is_not_null()

	var prev_platform = hp._detected_platform
	var prev_profile = hp._detected_profile
	var prev_streak = hp._web_fps_below_streak
	var prev_cooldown = hp._web_degrade_cooldown_sec

	hp._detected_platform = HardwareProfileScript.PlatformType.HTML5
	hp._detected_profile = HardwareProfileScript.Profile.HIGH
	hp._web_fps_below_streak = 0
	hp._web_degrade_cooldown_sec = 0.0

	hp._degrade_web_profile_due_to_fps(20.0)
	assert_int(hp._detected_profile).is_equal(HardwareProfileScript.Profile.MEDIUM)

	hp._web_degrade_cooldown_sec = 0.0
	hp._degrade_web_profile_due_to_fps(20.0)
	assert_int(hp._detected_profile).is_equal(HardwareProfileScript.Profile.MEDIUM)

	hp._detected_platform = prev_platform
	hp._detected_profile = prev_profile
	hp._web_fps_below_streak = prev_streak
	hp._web_degrade_cooldown_sec = prev_cooldown


func test_html5_auto_estimate_never_starts_below_medium() -> void:
	var hp = get_tree().root.get_node_or_null("HardwareProfile")
	assert_object(hp).is_not_null()

	var prev_cores = hp._processor_count
	var prev_mem = hp._cached_memory_total_gb

	hp._processor_count = 2
	hp._cached_memory_total_gb = 1.5

	assert_int(hp._estimate_html5_profile()).is_equal(HardwareProfileScript.Profile.MEDIUM)

	hp._processor_count = prev_cores
	hp._cached_memory_total_gb = prev_mem


func test_html5_medium_profile_is_not_marked_as_weak_hardware() -> void:
	var hp = get_tree().root.get_node_or_null("HardwareProfile")
	assert_object(hp).is_not_null()

	var prev_platform = hp._detected_platform
	var prev_profile = hp._detected_profile
	var prev_cores = hp._processor_count
	var prev_mem = hp._cached_memory_total_gb

	hp._detected_platform = HardwareProfileScript.PlatformType.HTML5
	hp._detected_profile = HardwareProfileScript.Profile.MEDIUM
	hp._processor_count = 2
	hp._cached_memory_total_gb = 1.5

	assert_bool(hp._detect_weak_hardware()).is_false()

	hp._detected_platform = prev_platform
	hp._detected_profile = prev_profile
	hp._processor_count = prev_cores
	hp._cached_memory_total_gb = prev_mem


func test_non_html5_adaptive_degrade_can_reach_low() -> void:
	var hp = get_tree().root.get_node_or_null("HardwareProfile")
	assert_object(hp).is_not_null()

	var prev_platform = hp._detected_platform
	var prev_profile = hp._detected_profile
	var prev_streak = hp._web_fps_below_streak
	var prev_cooldown = hp._web_degrade_cooldown_sec

	hp._detected_platform = HardwareProfileScript.PlatformType.LINUX_X86
	hp._detected_profile = HardwareProfileScript.Profile.MEDIUM
	hp._web_fps_below_streak = 0
	hp._web_degrade_cooldown_sec = 0.0

	hp._degrade_web_profile_due_to_fps(20.0)
	assert_int(hp._detected_profile).is_equal(HardwareProfileScript.Profile.LOW)

	hp._detected_platform = prev_platform
	hp._detected_profile = prev_profile
	hp._web_fps_below_streak = prev_streak
	hp._web_degrade_cooldown_sec = prev_cooldown
