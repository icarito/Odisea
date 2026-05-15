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
