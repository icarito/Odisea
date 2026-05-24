extends GdUnitTestSuite

func test_find_dome_id_by_interior_spawn_supports_shared_interior_scenes() -> void:
	assert_str(DomeRegistry.find_dome_id_by_interior_spawn("from_exterior_dome_01")).is_equal("dome_01")
	assert_str(DomeRegistry.find_dome_id_by_interior_spawn("from_exterior_dome_02")).is_equal("dome_02")
	assert_str(DomeRegistry.find_dome_id_by_interior_spawn("from_exterior_dome_03")).is_equal("dome_03")

func test_find_dome_id_by_exterior_spawn_supports_shared_interior_scenes() -> void:
	assert_str(DomeRegistry.find_dome_id_by_exterior_spawn("from_dome_01")).is_equal("dome_01")
	assert_str(DomeRegistry.find_dome_id_by_exterior_spawn("from_dome_02")).is_equal("dome_02")
	assert_str(DomeRegistry.find_dome_id_by_exterior_spawn("from_dome_03")).is_equal("dome_03")