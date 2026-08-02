extends GdUnitTestSuite

const RadialScatterScript = preload("res://core_v2/tools/RadialScatter.gd")
const SteelGratePlatformScript = preload("res://core_v2/props/scaffold/SteelGratePlatform.gd")

func test_dynamic_track_moves_only_the_requested_scaffold_side() -> void:
	var scatter = auto_free(RadialScatterScript.new())
	var platform = auto_free(SteelGratePlatformScript.new())
	scatter.dynamic_float_properties = ["right_height_offset"]
	scatter.dynamic_float_start = [0.0]
	scatter.dynamic_float_end = [2.0]
	scatter._apply_dynamic_float_properties(platform, 1.0)

	assert_float(platform.left_height_offset).is_equal(0.0)
	assert_float(platform.right_height_offset).is_equal(2.0)
	assert_float(platform._deck_top_y_at(-2.0, 0.0)).is_equal(platform.platform_height)
	assert_float(platform._deck_top_y_at(2.0, 0.0)).is_equal(platform.platform_height + 2.0)

func test_depth_offsets_create_a_mitered_trapezoid_for_spiral_chunks() -> void:
	var platform = auto_free(SteelGratePlatformScript.new())
	platform.platform_width = 4.0
	platform.platform_depth = 10.0
	platform.left_depth_offset = 0.39
	platform.right_depth_offset = -0.39

	var outer_front: Vector3 = platform._deck_point(-2.0, -1.0)
	var inner_front: Vector3 = platform._deck_point(2.0, -1.0)

	assert_float(outer_front.z).is_equal_approx(-5.39, 0.001)
	assert_float(inner_front.z).is_equal_approx(-4.61, 0.001)

func test_spiral_tangent_correction_compensates_inward_radius_change() -> void:
	var scatter = auto_free(RadialScatterScript.new())
	scatter.radius_per_turn = -4.0

	assert_float(scatter._get_spiral_tangent_correction_deg(26.0)).is_equal_approx(-1.403, 0.001)

func test_eased_radius_pulls_the_spiral_inward_near_its_end() -> void:
	var scatter = auto_free(RadialScatterScript.new())
	scatter.radius = 26.0
	scatter.radius_per_turn = -12.0
	scatter.radius_ease_power = 2.0

	assert_float(scatter._get_radius_at_turn(0.5)).is_equal_approx(23.0, 0.001)
	assert_float(scatter._get_radius_at_turn(1.0)).is_equal_approx(14.0, 0.001)

func test_interleaved_chords_share_their_join() -> void:
	var stairs = auto_free(RadialScatterScript.new())
	stairs.radius = 26.0
	stairs.radius_per_turn = -12.0
	stairs.radius_ease_power = 2.0
	stairs.spiral_segment_angle_deg = 30.0
	var walkway = auto_free(RadialScatterScript.new())
	walkway.radius = 26.0
	walkway.radius_per_turn = -12.0
	walkway.radius_ease_power = 2.0
	walkway.spiral_segment_angle_deg = 30.0

	var stair_end: Vector3 = stairs._get_spiral_chord_end(0.0, 0.0)
	var walkway_start: Vector3 = walkway._get_spiral_chord_start(deg2rad(30.0), 30.0 / 360.0)
	assert_float(stair_end.distance_to(walkway_start)).is_less(0.001)

func test_sloped_stair_rails_use_inclined_collision() -> void:
	var platform = auto_free(SteelGratePlatformScript.new())
	platform.platform_width = 4.0
	platform.platform_depth = 10.0
	platform.front_height_offset = 2.0
	platform.rail_left = true
	platform.rail_right = true
	platform._ensure_structure()
	platform._rebuild()

	var left_rail = platform.get_node("StaticBody/LeftRailCollision") as CollisionShape
	assert_bool(left_rail.shape is ConvexPolygonShape).is_true()
	assert_int((left_rail.shape as ConvexPolygonShape).points.size()).is_equal(8)
