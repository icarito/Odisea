extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const AudioManagerScript = preload("res://core_v2/autoloads/AudioManager.gd")
const BGMZoneScript = preload("res://core_v2/components/BGMZoneV2.gd")

func test_bgm_zone_inheritance():
	var zone = BGMZoneScript.new()
	assert_object(zone).is_instanceof(BaseZoneV2)
	assert_bool(zone.has_method("get_volume")).is_true()
	zone.free()

func test_audio_manager_sorting():
	var am = AudioManagerScript.new()

	var zone_large = BGMZoneScript.new()
	var zone_small = BGMZoneScript.new()

	# BaseZoneV2 uses zone_extents for get_volume()
	zone_large.zone_extents = Vector3(10, 10, 10) # Volume = 10*10*10*8 = 8000
	zone_small.zone_extents = Vector3(1, 1, 1)    # Volume = 1*1*1*8 = 8

	# Check sort function: _sort_zones(a, b) returns true if a < b (a is higher priority/smaller)
	# So zone_small < zone_large should be true
	var result = am._sort_zones(zone_small, zone_large)
	assert_bool(result).is_true()

	result = am._sort_zones(zone_large, zone_small)
	assert_bool(result).is_false()

	zone_large.free()
	zone_small.free()
	am.free()

func test_mobile_web_audio_guard_detection():
	var am = AudioManagerScript.new()

	assert_bool(am._should_enable_mobile_web_audio_guard("HTML5", true)).is_true()
	assert_bool(am._should_enable_mobile_web_audio_guard("HTML5", false)).is_false()
	assert_bool(am._should_enable_mobile_web_audio_guard("Android", true)).is_false()

	am.free()

func test_mobile_web_audio_policy_pauses_out_of_range_players():
	var am = AudioManagerScript.new()
	var player = AudioStreamPlayer3D.new()
	player.max_distance = 24.0
	player.out_of_range_mode = AudioStreamPlayer3D.OUT_OF_RANGE_MIX

	am._configure_mobile_web_3d_player(player)

	assert_int(player.out_of_range_mode).is_equal(AudioStreamPlayer3D.OUT_OF_RANGE_PAUSE)

	player.free()
	am.free()

func test_mobile_web_audio_policy_keeps_unbounded_players_mixing():
	var am = AudioManagerScript.new()
	var player = AudioStreamPlayer3D.new()
	player.max_distance = 0.0
	player.out_of_range_mode = AudioStreamPlayer3D.OUT_OF_RANGE_MIX

	am._configure_mobile_web_3d_player(player)

	assert_int(player.out_of_range_mode).is_equal(AudioStreamPlayer3D.OUT_OF_RANGE_MIX)

	player.free()
	am.free()
