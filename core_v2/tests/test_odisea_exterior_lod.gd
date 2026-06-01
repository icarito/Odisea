extends GdUnitTestSuite

const OdiseaExteriorScript = preload("res://core_v2/levels/OdiseaExterior.gd")

func test_extract_dome_lod_blueprint_collects_all_meshes_with_hierarchy() -> void:
	var exterior = auto_free(OdiseaExteriorScript.new())

	var root = auto_free(Spatial.new())
	var pivot = auto_free(Spatial.new())
	pivot.transform.origin = Vector3(10, 5, -3)
	root.add_child(pivot)

	var mesh_a = auto_free(MeshInstance.new())
	mesh_a.mesh = CubeMesh.new()
	mesh_a.transform.origin = Vector3(2, 0, 0)
	pivot.add_child(mesh_a)

	var nested = auto_free(Spatial.new())
	nested.transform.origin = Vector3(0, 4, 1)
	pivot.add_child(nested)

	var mesh_b = auto_free(MeshInstance.new())
	mesh_b.mesh = SphereMesh.new()
	mesh_b.transform.origin = Vector3(-1, 0, 6)
	nested.add_child(mesh_b)

	var blueprint: Dictionary = exterior._extract_dome_lod_blueprint(root, "")
	var parts: Array = blueprint.get("parts", [])

	assert_int(parts.size()).is_equal(2)
	assert_vector3(parts[0]["local_transform"].origin).is_equal(Vector3(12, 5, -3))
	assert_vector3(parts[1]["local_transform"].origin).is_equal(Vector3(9, 9, 4))

func test_resolve_uniform_fit_scale_for_sizes_matches_reference_bounds() -> void:
	var exterior = auto_free(OdiseaExteriorScript.new())
	assert_float(exterior._resolve_uniform_fit_scale_for_sizes(Vector3(125, 65, 125), Vector3(62.5, 32.5, 62.5))).is_equal_approx(0.5, 0.0001)

func test_prewarm_full_detail_dome_covers_one_ring_beyond_visible_radius() -> void:
	var exterior = auto_free(OdiseaExteriorScript.new())
	exterior.dome_full_detail_plate_radius = 0
	exterior.dome_full_detail_preload_extra_radius = 1
	assert_bool(exterior._is_distance_within_full_detail_prewarm(1)).is_true()
	assert_bool(exterior._is_distance_within_full_detail_prewarm(2)).is_false()

func test_local_full_detail_window_is_capped_to_three_plates() -> void:
	var exterior = auto_free(OdiseaExteriorScript.new())
	var keys: Dictionary = exterior._get_local_plate_window_keys(2, 0, 10, 3)

	assert_int(keys.size()).is_equal(3)
	assert_bool(keys.has("2:0")).is_true()
	assert_bool(keys.has("2:9")).is_true()
	assert_bool(keys.has("2:1")).is_true()

func test_select_nearest_lod_assignments_returns_all_when_under_budget() -> void:
	var exterior = auto_free(OdiseaExteriorScript.new())
	exterior.dome_lod_overlay_max_instances = 64
	var assignments := [{"spiral_index": 0, "plate_index": 0}, {"spiral_index": 0, "plate_index": 1}]
	var result := exterior._select_nearest_dome_lod_assignments(assignments)
	assert_int(result.size()).is_equal(2)

func test_select_nearest_lod_assignments_slices_when_rotator_null() -> void:
	var exterior = auto_free(OdiseaExteriorScript.new())
	exterior.dome_lod_overlay_max_instances = 2
	var assignments := []
	for i in range(5):
		assignments.append({"spiral_index": 0, "plate_index": i})
	var result := exterior._select_nearest_dome_lod_assignments(assignments)
	assert_int(result.size()).is_equal(2)

func test_insert_ranked_lod_entry_keeps_sorted_nearest_first() -> void:
	var exterior = auto_free(OdiseaExteriorScript.new())
	var ranked := []
	exterior._insert_ranked_lod_entry(ranked, {"dist_sq": 100.0}, 3)
	exterior._insert_ranked_lod_entry(ranked, {"dist_sq": 10.0}, 3)
	exterior._insert_ranked_lod_entry(ranked, {"dist_sq": 50.0}, 3)
	exterior._insert_ranked_lod_entry(ranked, {"dist_sq": 5.0}, 3)
	assert_int(ranked.size()).is_equal(3)
	assert_float(ranked[0].get("dist_sq")).is_equal(5.0)
	assert_float(ranked[1].get("dist_sq")).is_equal(10.0)
	assert_float(ranked[2].get("dist_sq")).is_equal(50.0)
