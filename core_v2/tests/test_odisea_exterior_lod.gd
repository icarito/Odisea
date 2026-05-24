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
