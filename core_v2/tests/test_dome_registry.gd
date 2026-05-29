extends GdUnitTestSuite

func test_find_dome_id_by_interior_spawn_supports_shared_interior_scenes() -> void:
	assert_str(DomeRegistry.find_dome_id_by_interior_spawn("from_exterior_dome_01")).is_equal("dome_01")
	assert_str(DomeRegistry.find_dome_id_by_interior_spawn("from_exterior_dome_02")).is_equal("dome_02")
	assert_str(DomeRegistry.find_dome_id_by_interior_spawn("from_exterior_dome_03")).is_equal("dome_03")

func test_find_dome_id_by_exterior_spawn_supports_shared_interior_scenes() -> void:
	assert_str(DomeRegistry.find_dome_id_by_exterior_spawn("from_dome_01")).is_equal("dome_01")
	assert_str(DomeRegistry.find_dome_id_by_exterior_spawn("from_dome_02")).is_equal("dome_02")
	assert_str(DomeRegistry.find_dome_id_by_exterior_spawn("from_dome_03")).is_equal("dome_03")

func test_get_facade_lod_config_returns_safe_defaults() -> void:
	var lod_config := DomeRegistry.get_facade_lod_config("dome_01")
	assert_dict(lod_config).contains_keys(["scene", "mesh_node", "mesh", "spawn_offset", "scale"])
	assert_str(String(lod_config["scene"])).is_equal("res://models/lod/DomeFacade_01_LOD.glb")
	assert_str(String(lod_config["mesh"])).is_equal("")
	assert_vector3(lod_config["spawn_offset"]).is_equal(Vector3(0, 0.3, 0))
	assert_vector3(lod_config["scale"]).is_equal(Vector3.ONE)

func test_get_dome_id_for_plate_uses_explicit_then_synthetic_ids() -> void:
	assert_str(DomeRegistry.get_dome_id_for_plate(0, 0)).is_equal("dome_01")
	assert_str(DomeRegistry.get_dome_id_for_plate(3, 17)).is_equal("dome_s03_p017")

func test_get_dome_builds_synthetic_defaults_for_unregistered_plate() -> void:
	var info := DomeRegistry.get_dome("dome_s03_p017")
	assert_str(String(info.get("facade_scene", ""))).is_equal("res://core_v2/levels/facades/DomeFacade_01.tscn")
	assert_str(String(info.get("spawn_id_from_exterior", ""))).is_equal("from_dome_s03_p017")
	assert_str(String(info.get("spawn_id_from_interior", ""))).is_equal("from_exterior_dome_s03_p017")
	assert_int(int(info.get("spiral_index", -1))).is_equal(3)
	assert_int(int(info.get("plate_index", -1))).is_equal(17)

func test_find_dome_id_by_synthetic_spawn_ids() -> void:
	assert_str(DomeRegistry.find_dome_id_by_exterior_spawn("from_dome_s03_p017")).is_equal("dome_s03_p017")
	assert_str(DomeRegistry.find_dome_id_by_interior_spawn("from_exterior_dome_s03_p017")).is_equal("dome_s03_p017")