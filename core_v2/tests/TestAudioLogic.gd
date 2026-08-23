extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const AudioManagerScript = preload("res://core_v2/autoloads/AudioManager.gd")
const BGMZoneScript = preload("res://core_v2/components/BGMZoneV2.gd")
const MenuScript = preload("res://core_v2/ui/Menu.gd")

func test_bgm_zone_inheritance():
	var zone = BGMZoneScript.new()
	assert_object(zone).is_instanceof(BaseZoneV2)
	assert_bool(zone.has_method("get_volume")).is_true()
	zone.free()


func test_empty_bgm_zone_does_not_override_parent_music():
	var zone = BGMZoneScript.new()
	assert_bool(zone.has_bgm_content()).is_false()
	zone.song_name = "cabin_theme"
	assert_bool(zone.has_bgm_content()).is_true()
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

func test_audio_manager_bgm_players_use_music_bus():
	var am = AudioManagerScript.new()
	am._ready()

	assert_str(am._bgm_player_1.bus).is_equal("Music")
	assert_str(am._bgm_player_2.bus).is_equal("Music")

	am.free()

func test_menu_bgm_uses_music_bus_and_lifecycle():
	var menu_scene = load("res://scenes/Menu.tscn") as PackedScene
	assert_object(menu_scene).is_not_null()
	var menu = menu_scene.instance()
	add_child(menu)

	var bgm_player = menu.get_node_or_null("MenuBGM") as AudioStreamPlayer
	assert_object(bgm_player).is_not_null()
	assert_str(bgm_player.bus).is_equal("Music")
	assert_bool(bgm_player.playing).is_true()

	menu._stop_bgm()
	assert_bool(bgm_player.playing).is_false()

	menu.queue_free()

func test_music_paused_by_menu_alone():
	var am = AudioManagerScript.new()
	assert_bool(am.is_music_paused()).is_false()

	am.set_music_paused_by_menu(true)
	assert_bool(am.is_music_paused()).is_true()

	am.set_music_paused_by_menu(false)
	assert_bool(am.is_music_paused()).is_false()

	am.free()

func test_music_pause_focus_and_menu_combinations():
	var am = AudioManagerScript.new()

	# Case 1: Menu pause -> Focus lost -> Focus gained -> Menu resume
	am.set_music_paused_by_menu(true)
	assert_bool(am.is_music_paused()).is_true()

	am._set_music_focus_paused(true)
	assert_bool(am.is_music_paused()).is_true()

	am._set_music_focus_paused(false)
	assert_bool(am.is_music_paused()).is_true() # Still paused by menu!

	am.set_music_paused_by_menu(false)
	assert_bool(am.is_music_paused()).is_false()

	# Case 2: Focus lost -> Menu pause -> Focus gained -> Menu resume
	am._set_music_focus_paused(true)
	assert_bool(am.is_music_paused()).is_true()

	am.set_music_paused_by_menu(true)
	assert_bool(am.is_music_paused()).is_true()

	am._set_music_focus_paused(false)
	assert_bool(am.is_music_paused()).is_true() # Still paused by menu!

	am.set_music_paused_by_menu(false)
	assert_bool(am.is_music_paused()).is_false()

	# Case 3: Redundant calls (idempotency)
	am.set_music_paused_by_menu(true)
	am.set_music_paused_by_menu(true)
	assert_bool(am.is_music_paused()).is_true()

	am.set_music_paused_by_menu(false)
	am.set_music_paused_by_menu(false)
	assert_bool(am.is_music_paused()).is_false()

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
