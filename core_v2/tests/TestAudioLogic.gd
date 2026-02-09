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
