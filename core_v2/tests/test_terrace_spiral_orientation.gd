extends GdUnitTestSuite

const TerraceSpiralScript = preload("res://core_v2/components/TerraceSpiral.gd")

func test_full_tilt_normals_face_spiral_axis_with_interlock() -> void:
	var spiral = auto_free(TerraceSpiralScript.new())
	var samples := [0.0, PI * 0.5, PI, PI * 1.5]

	for theta in samples:
		var basis: Basis = spiral._build_plate_basis(theta, deg2rad(-90.0), deg2rad(45.0))
		var inward := Vector3(-cos(theta), 0.0, -sin(theta)).normalized()
		var normal := basis.y.normalized()

		assert_float(normal.dot(inward)).is_greater_equal(0.999)

func test_zero_tilt_keeps_terrace_normal_vertical() -> void:
	var spiral = auto_free(TerraceSpiralScript.new())
	var basis: Basis = spiral._build_plate_basis(PI * 0.75, 0.0, deg2rad(45.0))

	assert_float(basis.y.normalized().dot(Vector3.UP)).is_greater_equal(0.999)

func test_dome_lod_overlays_follow_cached_plate_transforms() -> void:
	var spiral = auto_free(TerraceSpiralScript.new())
	spiral.plate_mesh = CubeMesh.new()
	spiral.total_height = 120.0
	spiral.plate_step = 40.0
	spiral.animate = false
	spiral.manual_blend = 0.0
	spiral._rebuild_multimesh_if_needed()
	spiral._update_spiral_animation()

	var overlay_mesh := CubeMesh.new()
	spiral.set_dome_lod_overlays([{
		"key": "dome",
		"parts": [{
			"mesh": overlay_mesh,
			"material_override": null,
			"items": [{
				"plate_index": 1,
				"local_transform": Transform(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)),
				"origin_offset": Vector3(0.0, 0.3, 0.0)
			}],
			"signature": "dome|part0|1"
		}]
	}])

	var overlay_root: Spatial = spiral.get_node_or_null("DomeLOD") as Spatial
	assert_object(overlay_root).is_not_null()
	var overlay_instance: MultiMeshInstance = overlay_root.get_node_or_null("DomeLOD_0_0") as MultiMeshInstance
	assert_object(overlay_instance).is_not_null()
	var expected: Transform = spiral._cached_transforms[1] * Transform(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
	expected.origin += Vector3(0.0, 0.3, 0.0)
	var actual: Transform = overlay_instance.multimesh.get_instance_transform(0)
	assert_float(actual.origin.distance_to(expected.origin)).is_less(0.001)
