extends GdUnitTestSuite

const TerraceSegmentManagerScript = preload("res://core_v2/systems/visual/TerraceSegmentManager.gd")

func test_full_detail_plate_keys_wrap_around_selected_plate() -> void:
	var manager = auto_free(TerraceSegmentManagerScript.new())
	manager.full_detail_plate_radius = 2

	var keys: Dictionary = manager.get_full_detail_plate_keys(1, 0, 10)

	assert_bool(keys.has("1:8")).is_true()
	assert_bool(keys.has("1:9")).is_true()
	assert_bool(keys.has("1:0")).is_true()
	assert_bool(keys.has("1:1")).is_true()
	assert_bool(keys.has("1:2")).is_true()
	assert_int(keys.size()).is_equal(5)

func test_build_stats_counts_lod_and_full_detail_plates() -> void:
	var manager = auto_free(TerraceSegmentManagerScript.new())
	var assignments := [
		{"spiral_index": 0, "plate_index": 1},
		{"spiral_index": 0, "plate_index": 2},
		{"spiral_index": 0, "plate_index": 3}
	]
	var full_detail := {"0:2": true}

	var stats: Dictionary = manager.build_stats(assignments, full_detail, 4, true)

	assert_int(stats["total_assignments"]).is_equal(3)
	assert_int(stats["lod1_instances"]).is_equal(2)
	assert_int(stats["lod2_full_detail_plates"]).is_equal(1)
	assert_int(stats["estimated_lod_draw_surfaces"]).is_equal(5)

func test_nearest_full_detail_keys_use_spatial_distance_across_spirals() -> void:
	var manager = auto_free(TerraceSegmentManagerScript.new())
	var candidates := [
		{"spiral_index": 0, "plate_index": 10, "origin": Vector3(100, 0, 0)},
		{"spiral_index": 1, "plate_index": 3, "origin": Vector3(1, 0, 0)},
		{"spiral_index": 2, "plate_index": 8, "origin": Vector3(0, 2, 0)},
		{"spiral_index": 0, "plate_index": 11, "origin": Vector3(50, 0, 0)}
	]

	var keys: Dictionary = manager.get_nearest_full_detail_plate_keys(candidates, Vector3.ZERO, 2)

	assert_int(keys.size()).is_equal(2)
	assert_bool(keys.has("1:3")).is_true()
	assert_bool(keys.has("2:8")).is_true()
	assert_bool(keys.has("0:10")).is_false()
