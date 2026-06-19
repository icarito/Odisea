extends GdUnitTestSuite

const TEST_SCENE := "res://core_v2/props/doors/AirlockChamber.tscn"

func test_scene_preload_finishes_and_reuses_cached_packed_scene() -> void:
	var scene_manager := get_node_or_null("/root/SceneManager")
	assert_object(scene_manager).is_not_null()
	if scene_manager == null:
		return

	assert_bool(scene_manager.request_scene_preload(TEST_SCENE)).is_true()
	var deadline_ms := OS.get_ticks_msec() + 5000
	while scene_manager.is_scene_preloading(TEST_SCENE) and OS.get_ticks_msec() < deadline_ms:
		yield(get_tree(), "idle_frame")

	assert_bool(scene_manager.has_preloaded_scene(TEST_SCENE)).is_true()
	assert_object(scene_manager.get_preloaded_scene(TEST_SCENE)).is_instanceof(PackedScene)
	assert_bool(scene_manager.request_scene_preload(TEST_SCENE)).is_true()
	assert_bool(scene_manager.is_scene_preloading(TEST_SCENE)).is_false()
